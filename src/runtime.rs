//! One Luau VM per UI file: loads the prelude, runs the module, renders it to
//! a JSON tree and dispatches UI events back into Luau.

use mlua::serde::DeserializeOptions;
use mlua::{Function, Lua, LuaSerdeExt, Table, Value, VmState};
use serde::Serialize;
use serde_json::Value as Json;
use std::cell::{Cell, RefCell};
use std::path::{Component, Path, PathBuf};
use std::rc::Rc;
use std::time::{Duration, Instant};

const PRELUDE: &str = include_str!("prelude.luau");
const BUDGET: Duration = Duration::from_millis(2000);

#[derive(Debug, Clone, Serialize)]
pub struct LogLine {
    pub kind: String,
    pub text: String,
}

pub struct UiSession {
    lua: Lua,
    root: PathBuf,
    deadline: Rc<Cell<Instant>>,
    logs: Rc<RefCell<Vec<LogLine>>>,
}

/// Forward-slash string form of a path.
pub fn slash(p: &Path) -> String {
    p.to_string_lossy().replace('\\', "/")
}

/// Lexically normalizes `.` and `..` without touching the disk.
pub fn normalize(p: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for c in p.components() {
        match c {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    out
}

fn within(root: &Path, p: &Path) -> bool {
    let r = slash(root).to_lowercase();
    let q = slash(p).to_lowercase();
    q == r || q.starts_with(&(r.trim_end_matches('/').to_string() + "/"))
}

/// Finds a module file for a path without extension.
pub fn find_module(root: &Path, base: &str) -> Option<PathBuf> {
    let p = normalize(Path::new(base));
    if !within(root, &p) {
        return None;
    }
    let s = slash(&p);
    let candidates = [
        s.clone(),
        format!("{s}.luau"),
        format!("{s}.lua"),
        format!("{s}/init.luau"),
        format!("{s}/init.lua"),
    ];
    for c in candidates {
        let cp = PathBuf::from(&c);
        if cp.is_file() {
            let ext = cp.extension().and_then(|e| e.to_str()).unwrap_or("");
            if ext == "luau" || ext == "lua" {
                return Some(cp);
            }
        }
    }
    None
}

impl UiSession {
    pub fn new(root: &Path, file: &Path, device: (f64, f64)) -> Result<Self, String> {
        let lua = Lua::new();
        let _ = lua.set_memory_limit(512 * 1024 * 1024);
        let deadline = Rc::new(Cell::new(Instant::now() + BUDGET));
        let logs: Rc<RefCell<Vec<LogLine>>> = Rc::new(RefCell::new(Vec::new()));
        let root = normalize(root);
        let file = normalize(file);

        {
            let d = deadline.clone();
            lua.set_interrupt(move |_| {
                if Instant::now() > d.get() {
                    Err(mlua::Error::runtime(
                        "execution time exceeded (2 s): infinite loop?",
                    ))
                } else {
                    Ok(VmState::Continue)
                }
            });
        }

        let host = build_host(&lua, &root, &file, device, logs.clone()).map_err(|e| e.to_string())?;
        lua.globals().set("__HOST", host).map_err(|e| e.to_string())?;
        lua.load(PRELUDE)
            .set_name("=luauui-prelude")
            .exec()
            .map_err(|e| format!("prelude: {e}"))?;

        Ok(Self { lua, root, deadline, logs })
    }

    fn arm(&self) {
        self.deadline.set(Instant::now() + BUDGET);
    }

    fn clean_err(&self, e: mlua::Error) -> String {
        let mut s = e.to_string();
        let root = slash(&self.root);
        s = s.replace(&format!("{root}/"), "");
        s = s.replace("runtime error: ", "");
        // drop prelude frames from tracebacks
        s.lines()
            .filter(|l| !l.contains("luauui-prelude"))
            .collect::<Vec<_>>()
            .join("\n")
    }

    pub fn load(&self) -> Result<(), String> {
        self.arm();
        let f: Function = self.lua.globals().get("__luauui_load").map_err(|e| e.to_string())?;
        f.call::<()>(()).map_err(|e| self.clean_err(e))
    }

    pub fn render(&self) -> Result<Json, String> {
        self.arm();
        let f: Function = self.lua.globals().get("__luauui_render").map_err(|e| e.to_string())?;
        let v: Value = f.call(()).map_err(|e| self.clean_err(e))?;
        let opts = DeserializeOptions::new()
            .deny_unsupported_types(false)
            .deny_recursive_tables(false)
            .encode_empty_tables_as_array(true);
        self.lua
            .from_value_with::<Json>(v, opts)
            .map_err(|e| format!("serialization: {e}"))
    }

    pub fn fire(&self, id: i64, payload: &Json) -> Result<bool, String> {
        self.arm();
        let f: Function = self.lua.globals().get("__luauui_fire").map_err(|e| e.to_string())?;
        let p = self.lua.to_value(payload).map_err(|e| e.to_string())?;
        f.call::<bool>((id, p)).map_err(|e| self.clean_err(e))
    }

    pub fn take_logs(&self) -> Vec<LogLine> {
        std::mem::take(&mut *self.logs.borrow_mut())
    }
}

fn build_host(
    lua: &Lua,
    root: &Path,
    file: &Path,
    device: (f64, f64),
    logs: Rc<RefCell<Vec<LogLine>>>,
) -> mlua::Result<Table> {
    let host = lua.create_table()?;
    host.set("root", slash(root))?;
    host.set("file", slash(file))?;

    host.set(
        "device",
        lua.create_function(move |_, ()| Ok((device.0, device.1)))?,
    )?;

    {
        let logs = logs.clone();
        let root_s = slash(root);
        host.set(
            "log",
            lua.create_function(move |_, (kind, text): (String, String)| {
                let mut l = logs.borrow_mut();
                if l.len() < 500 {
                    l.push(LogLine { kind, text: text.replace(&format!("{root_s}/"), "") });
                }
                Ok(())
            })?,
        )?;
    }

    {
        let root = root.to_path_buf();
        host.set(
            "find",
            lua.create_function(move |_, base: String| {
                Ok(find_module(&root, &base).map(|p| slash(&p)))
            })?,
        )?;
    }

    {
        let root = root.to_path_buf();
        host.set(
            "isfile",
            lua.create_function(move |_, p: String| {
                let pb = PathBuf::from(&p);
                Ok(within(&root, &pb) && pb.is_file())
            })?,
        )?;
    }

    {
        let root = root.to_path_buf();
        host.set(
            "load",
            lua.create_function(move |lua, p: String| {
                let pb = normalize(Path::new(&p));
                if !within(&root, &pb) {
                    return Err(mlua::Error::runtime(format!("access denied outside the project: {p}")));
                }
                let src = std::fs::read_to_string(&pb)
                    .map_err(|e| mlua::Error::runtime(format!("reading {p}: {e}")))?;
                let src = src.trim_start_matches('\u{feff}');
                lua.load(src).set_name(format!("@{}", slash(&pb))).into_function()
            })?,
        )?;
    }

    host.set(
        "json_encode",
        lua.create_function(|lua, v: Value| {
            let opts = DeserializeOptions::new().deny_unsupported_types(false);
            let j: Json = lua.from_value_with(v, opts)?;
            Ok(j.to_string())
        })?,
    )?;
    host.set(
        "json_decode",
        lua.create_function(|lua, s: String| {
            let j: Json = serde_json::from_str(&s).map_err(mlua::Error::external)?;
            lua.to_value(&j)
        })?,
    )?;

    Ok(host)
}

/// Result of rendering one UI file.
#[derive(Debug, Clone, Serialize, Default)]
pub struct RenderResult {
    pub ok: bool,
    pub roots: Json,
    pub error: Option<String>,
    pub logs: Vec<LogLine>,
    pub ms: f64,
    pub yielded: bool,
}

/// Loads and renders a UI file in a fresh session.
pub fn run_file(root: &Path, file: &Path, device: (f64, f64)) -> (Option<UiSession>, RenderResult) {
    let t0 = Instant::now();
    let session = match UiSession::new(root, file, device) {
        Ok(s) => s,
        Err(e) => {
            return (
                None,
                RenderResult { ok: false, roots: Json::Array(vec![]), error: Some(e), ..Default::default() },
            )
        }
    };
    let mut res = RenderResult { roots: Json::Array(vec![]), ..Default::default() };
    match session.load().and_then(|_| session.render()) {
        Ok(tree) => {
            res.ok = true;
            res.yielded = tree.get("yielded").and_then(|v| v.as_bool()).unwrap_or(false);
            res.roots = tree.get("roots").cloned().unwrap_or(Json::Array(vec![]));
        }
        Err(e) => res.error = Some(e),
    }
    res.logs = session.take_logs();
    res.ms = t0.elapsed().as_secs_f64() * 1000.0;
    (Some(session), res)
}

/// Re-renders an existing session (after an event).
pub fn rerender(session: &UiSession) -> RenderResult {
    let t0 = Instant::now();
    let mut res = RenderResult { roots: Json::Array(vec![]), ..Default::default() };
    match session.render() {
        Ok(tree) => {
            res.ok = true;
            res.yielded = tree.get("yielded").and_then(|v| v.as_bool()).unwrap_or(false);
            res.roots = tree.get("roots").cloned().unwrap_or(Json::Array(vec![]));
        }
        Err(e) => res.error = Some(e),
    }
    res.logs = session.take_logs();
    res.ms = t0.elapsed().as_secs_f64() * 1000.0;
    res
}
