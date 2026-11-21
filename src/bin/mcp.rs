//! LuauUI MCP server (stdio, JSON-RPC 2.0, one message per line).
//! Lets Claude create/edit Luau UI files, render them headless, and drive the
//! LuauUI Studio window (show/hide, click, layout check, screenshot).

use luauui::client;
use luauui::project::{self, Project, API_PORT, DEVICES};
use luauui::runtime::{self, slash};
use serde_json::{json, Value as Json};
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

const API_REFERENCE: &str = include_str!("../../docs/API.md");

struct Ctx {
    project: Option<PathBuf>,
}

fn api(method: &str, path: &str, body: Json, secs: u64) -> Result<Json, String> {
    let (code, text) = client::request(API_PORT, method, path, &body.to_string(), Duration::from_secs(secs))?;
    let v: Json = serde_json::from_str(&text).unwrap_or(json!({"raw": text}));
    if code >= 400 || code == 0 {
        return Err(v["error"].as_str().map(String::from).unwrap_or_else(|| format!("HTTP {code}: {text}")));
    }
    Ok(v)
}

fn app_state() -> Option<Json> {
    api("GET", "/state", json!({}), 3).ok()
}

fn enc(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'/' => out.push(b as char),
            _ => out.push_str(&format!("%{b:02X}")),
        }
    }
    out
}

impl Ctx {
    fn project(&self) -> Result<Project, String> {
        if let Some(st) = app_state() {
            if let Some(root) = st["root"].as_str() {
                return Ok(Project::open(Path::new(root)));
            }
        }
        if let Some(p) = &self.project {
            return Ok(Project::open(p));
        }
        let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
        if cwd.join("ui").is_dir() || cwd.join("luauui.json").is_file() {
            return Ok(Project::open(&cwd));
        }
        Err("No project: launch the app (launch_app with project) or call open_project with a folder.".into())
    }
}

fn text(s: impl Into<String>) -> Json {
    json!({"content": [{"type": "text", "text": s.into()}]})
}
fn fail(s: impl Into<String>) -> Json {
    json!({"content": [{"type": "text", "text": s.into()}], "isError": true})
}

fn tools() -> Json {
    let name = json!({"type": "string", "description": "UI name = path inside the ui/ folder without extension (e.g. \"Shop\", \"menus/Settings\")."});
    json!([
        {"name": "status", "description": "LuauUI state: whether the app is open, project, list of UIs (visible, errors), simulated device. Call this first.",
         "inputSchema": {"type": "object", "properties": {}}},
        {"name": "api_reference", "description": "Reference of what the preview supports: emulated Roblox API, LuauUI library (React/Roact), project conventions, limits. Read before writing a UI.",
         "inputSchema": {"type": "object", "properties": {}}},
        {"name": "list_uis", "description": "Lists the project's UI files (ui/**/*.luau, except files/folders starting with _).",
         "inputSchema": {"type": "object", "properties": {}}},
        {"name": "read_ui", "description": "Reads the Luau source of a UI.",
         "inputSchema": {"type": "object", "properties": {"name": name}, "required": ["name"]}},
        {"name": "write_ui", "description": "Creates or replaces a UI (ui/<name>.luau), reloads it, shows it in the app if open, and returns the rendered tree, Luau errors, print/warn output and layout problems (overflowing text, off-screen elements). The module must return a component (function), a createElement element, or an Instance (ScreenGui).",
         "inputSchema": {"type": "object", "properties": {"name": name, "source": {"type": "string", "description": "Full Luau source of the file."}, "show": {"type": "boolean", "description": "Show only this UI in the app (default true)."}}, "required": ["name", "source"]}},
        {"name": "write_module", "description": "Writes a shared module (theme, reusable component) at a path relative to the project, e.g. \"ui/_shared/Theme.luau\". Files/folders starting with _ are not listed as UIs.",
         "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}, "source": {"type": "string"}}, "required": ["path", "source"]}},
        {"name": "delete_ui", "description": "Deletes a UI (the file is moved to .luauui/trash and can be recovered).",
         "inputSchema": {"type": "object", "properties": {"name": name}, "required": ["name"]}},
        {"name": "render", "description": "Runs a UI and returns its tree (readable outline or full JSON), errors and logs. Uses the live app state if the app is open (after clicks), otherwise renders headless.",
         "inputSchema": {"type": "object", "properties": {"name": name, "format": {"type": "string", "enum": ["outline", "json"], "description": "default outline"}}, "required": ["name"]}},
        {"name": "show_ui", "description": "Shows a UI in the app. exclusive=true closes the others.",
         "inputSchema": {"type": "object", "properties": {"name": name, "exclusive": {"type": "boolean"}}, "required": ["name"]}},
        {"name": "hide_ui", "description": "Closes (hides) a UI in the app.",
         "inputSchema": {"type": "object", "properties": {"name": name}, "required": ["name"]}},
        {"name": "show_all", "description": "Shows all UIs.", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "hide_all", "description": "Closes all UIs.", "inputSchema": {"type": "object", "properties": {}}},
        {"name": "set_device", "description": "Changes the simulated device (resolution).",
         "inputSchema": {"type": "object", "properties": {"device": {"type": "string", "enum": DEVICES.iter().map(|d| d.id).collect::<Vec<_>>()}}, "required": ["device"]}},
        {"name": "get_layout", "description": "Real positions and sizes (device pixels) of every element of a UI in the app, with textOverflow / clipped / offscreen flags. Checks a layout without an image.",
         "inputSchema": {"type": "object", "properties": {"name": name}, "required": ["name"]}},
        {"name": "screenshot", "description": "PNG capture of the render in the app (the window must be open and not minimized). scope=viewport (simulated screen) or window (whole app).",
         "inputSchema": {"type": "object", "properties": {"name": {"type": "string", "description": "UI to show before the capture (optional)."}, "scope": {"type": "string", "enum": ["viewport", "window"]}}}},
        {"name": "click", "description": "Simulates a click (Activated / MouseButton1Click) on a UI element, then returns the new tree. node = path of names, e.g. \"Shop/Panel/BuyButton\".",
         "inputSchema": {"type": "object", "properties": {"name": name, "node": {"type": "string"}, "event": {"type": "string", "description": "Specific event (Activated, MouseEnter, ...). Optional."}}, "required": ["name", "node"]}},
        {"name": "type_text", "description": "Types text into a TextBox (fires Change.Text then FocusLost).",
         "inputSchema": {"type": "object", "properties": {"name": name, "node": {"type": "string"}, "text": {"type": "string"}, "enter": {"type": "boolean"}}, "required": ["name", "node", "text"]}},
        {"name": "reset_ui", "description": "Reloads a UI from disk (resets its state).",
         "inputSchema": {"type": "object", "properties": {"name": name}, "required": ["name"]}},
        {"name": "launch_app", "description": "Opens the LuauUI Studio window on a project (if it is not already open).",
         "inputSchema": {"type": "object", "properties": {"project": {"type": "string", "description": "Project folder (contains ui/)."}}}},
        {"name": "open_project", "description": "Switches project (in the app if open, otherwise for this MCP server).",
         "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}},
        {"name": "init_project", "description": "Creates a new LuauUI project (ui/ folder + example) at the given location.",
         "inputSchema": {"type": "object", "properties": {"path": {"type": "string"}}, "required": ["path"]}}
    ])
}

fn layout_issues(name: &str) -> Option<String> {
    let v = api("GET", &format!("/layout?name={}", enc(name)), json!({}), 15).ok()?;
    let mut lines = vec![];
    for n in v["nodes"].as_array()? {
        if !n["visible"].as_bool().unwrap_or(false) {
            continue;
        }
        let path = n["path"].as_str().unwrap_or("");
        if n["textOverflow"].as_bool() == Some(true) {
            lines.push(format!("- overflowing text: {path} ({}×{}, size {})", n["w"], n["h"], n["fontSize"]));
        }
        if n["offscreen"].as_bool() == Some(true) {
            lines.push(format!("- off-screen: {path} (x={}, y={})", n["x"], n["y"]));
        } else if n["clipped"].as_bool() == Some(true) {
            lines.push(format!("- crosses the screen edge: {path} (x={}, y={}, {}×{})", n["x"], n["y"], n["w"], n["h"]));
        }
    }
    let dev = &v["device"];
    Some(if lines.is_empty() {
        format!("Layout ({}×{}): no overflow detected.", dev["w"], dev["h"])
    } else {
        format!("Layout ({}×{}):\n{}", dev["w"], dev["h"], lines.join("\n"))
    })
}

fn summarize(name: &str, ok: bool, error: Option<&str>, logs: &Json, outline: &str, yielded: bool) -> String {
    let mut s = String::new();
    if ok {
        s.push_str(&format!("✔ {name} rendered without errors.\n"));
    } else {
        s.push_str(&format!("✘ {name}: Luau error\n{}\n", error.unwrap_or("?")));
    }
    if yielded {
        s.push_str("Note: the module called task.wait / :Wait() while loading; the preview stops at that point.\n");
    }
    if let Some(arr) = logs.as_array() {
        if !arr.is_empty() {
            s.push_str("Logs :\n");
            for l in arr.iter().take(40) {
                s.push_str(&format!("  [{}] {}\n", l["kind"].as_str().unwrap_or(""), l["text"].as_str().unwrap_or("")));
            }
        }
    }
    if ok {
        s.push_str("Tree:\n");
        s.push_str(outline);
    }
    s
}

fn render_headless(p: &Project, name: &str) -> Result<(bool, Option<String>, Json, String, bool, Json), String> {
    let path = find_ui_path(p, name)?;
    let (_s, res) = runtime::run_file(&p.root, &path, (1920.0, 1080.0));
    let outline = project::outline(&res.roots);
    let logs = serde_json::to_value(&res.logs).unwrap_or(json!([]));
    Ok((res.ok, res.error, logs, outline, res.yielded, res.roots))
}

fn find_ui_path(p: &Project, name: &str) -> Result<PathBuf, String> {
    p.find_uis()
        .into_iter()
        .find(|u| u.name == name)
        .map(|u| u.path)
        .ok_or_else(|| {
            let names: Vec<String> = p.find_uis().into_iter().map(|u| u.name).collect();
            format!("UI \"{name}\" not found. UIs: {}", names.join(", "))
        })
}

fn wait_for_app(secs: u64) -> bool {
    let end = std::time::Instant::now() + Duration::from_secs(secs);
    while std::time::Instant::now() < end {
        if app_state().is_some() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(250));
    }
    false
}

fn call(ctx: &mut Ctx, tool: &str, a: &Json) -> Json {
    let s = |k: &str| a[k].as_str().map(String::from);
    let name = s("name").unwrap_or_default();
    let running = app_state();
    let need_app = || -> Result<(), String> {
        if app_state().is_none() {
            Err("The LuauUI Studio app is not open. Call launch_app first.".into())
        } else {
            Ok(())
        }
    };
    let r: Result<Json, String> = (|| -> Result<Json, String> {
        match tool {
            "status" => {
                let p = ctx.project();
                let mut out = String::new();
                match &running {
                    Some(st) => {
                        out.push_str(&format!("App open · project {} ({})\nDevice: {}\n", st["project"].as_str().unwrap_or(""), st["root"].as_str().unwrap_or(""), st["device"]["label"].as_str().unwrap_or("")));
                        out.push_str("UIs :\n");
                        for u in st["uis"].as_array().cloned().unwrap_or_default() {
                            out.push_str(&format!(
                                "  - {} [{}]{}\n",
                                u["name"].as_str().unwrap_or(""),
                                if u["visible"].as_bool().unwrap_or(false) { "visible" } else { "hidden" },
                                u["error"].as_str().map(|e| format!(" ERROR: {}", e.lines().next().unwrap_or(""))).unwrap_or_default()
                            ));
                        }
                    }
                    None => {
                        out.push_str("App closed (launch_app to open it).\n");
                        match &p {
                            Ok(p) => {
                                out.push_str(&format!("Project: {} — UIs in {}:\n", slash(&p.root), slash(&p.ui_dir)));
                                for u in p.find_uis() {
                                    out.push_str(&format!("  - {}\n", u.name));
                                }
                            }
                            Err(e) => out.push_str(e),
                        }
                    }
                }
                Ok(text(out))
            }
            "api_reference" => Ok(text(API_REFERENCE)),
            "list_uis" => {
                let p = ctx.project()?;
                let uis: Vec<String> = p.find_uis().into_iter().map(|u| format!("{}  ({})", u.name, slash(u.path.strip_prefix(&p.root).unwrap_or(&u.path)))).collect();
                Ok(text(if uis.is_empty() { format!("No UI in {}", slash(&p.ui_dir)) } else { uis.join("\n") }))
            }
            "read_ui" => {
                let p = ctx.project()?;
                let path = find_ui_path(&p, &name)?;
                Ok(text(std::fs::read_to_string(path).map_err(|e| e.to_string())?))
            }
            "write_ui" => {
                let p = ctx.project()?;
                let source = s("source").ok_or("missing source")?;
                if !project::valid_name(&name) {
                    return Err("invalid name (letters, digits, _ - /)".into());
                }
                let path = p.ui_path(&name).ok_or("invalid name")?;
                if let Some(d) = path.parent() {
                    std::fs::create_dir_all(d).map_err(|e| e.to_string())?;
                }
                // keep an existing .lua extension if that's the file in place
                let lua_alt = path.with_extension("lua");
                let target = if !path.exists() && lua_alt.exists() { lua_alt } else { path };
                std::fs::write(&target, &source).map_err(|e| e.to_string())?;
                if running.is_some() {
                    std::thread::sleep(Duration::from_millis(120));
                    api("POST", "/reload", json!({"name": name}), 20)?;
                    let show = a["show"].as_bool().unwrap_or(true);
                    if show {
                        api("POST", "/only", json!({"name": name}), 10)?;
                    }
                    let t = api("GET", &format!("/tree?name={}", enc(&name)), json!({}), 10)?;
                    let mut out = summarize(&name, t["ok"].as_bool().unwrap_or(false), t["error"].as_str(), &t["logs"], t["outline"].as_str().unwrap_or(""), t["yielded"].as_bool().unwrap_or(false));
                    if show && t["ok"].as_bool().unwrap_or(false) {
                        if let Some(l) = layout_issues(&name) {
                            out.push('\n');
                            out.push_str(&l);
                        }
                    }
                    Ok(text(format!("Written: {}\n{out}", slash(&target))))
                } else {
                    let (ok, err, logs, outline, y, _) = render_headless(&p, &name)?;
                    Ok(text(format!("Written: {} (app closed: headless render)\n{}", slash(&target), summarize(&name, ok, err.as_deref(), &logs, &outline, y))))
                }
            }
            "write_module" => {
                let p = ctx.project()?;
                let rel = s("path").ok_or("missing path")?;
                let source = s("source").ok_or("missing source")?;
                let target = runtime::normalize(&p.root.join(&rel));
                if !slash(&target).to_lowercase().starts_with(&slash(&p.root).to_lowercase()) {
                    return Err("path outside the project".into());
                }
                if !matches!(target.extension().and_then(|e| e.to_str()), Some("luau" | "lua")) {
                    return Err("expected a .luau or .lua extension".into());
                }
                if let Some(d) = target.parent() {
                    std::fs::create_dir_all(d).map_err(|e| e.to_string())?;
                }
                std::fs::write(&target, source).map_err(|e| e.to_string())?;
                if running.is_some() {
                    std::thread::sleep(Duration::from_millis(120));
                    let st = api("POST", "/reload", json!({}), 30)?;
                    let errs: Vec<String> = st["uis"].as_array().cloned().unwrap_or_default().iter()
                        .filter_map(|u| u["error"].as_str().map(|e| format!("- {} : {}", u["name"].as_str().unwrap_or(""), e.lines().next().unwrap_or(""))))
                        .collect();
                    Ok(text(format!("Written: {}\n{}", slash(&target), if errs.is_empty() { "All UIs render without errors.".to_string() } else { format!("UIs with errors:\n{}", errs.join("\n")) })))
                } else {
                    Ok(text(format!("Written: {}", slash(&target))))
                }
            }
            "delete_ui" => {
                let p = ctx.project()?;
                let path = find_ui_path(&p, &name)?;
                let trash = p.root.join(".luauui").join("trash");
                std::fs::create_dir_all(&trash).map_err(|e| e.to_string())?;
                let stamp = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
                let dest = trash.join(format!("{}-{stamp}.luau", name.replace('/', "_")));
                std::fs::rename(&path, &dest).map_err(|e| e.to_string())?;
                Ok(text(format!("{name} moved to {}", slash(&dest))))
            }
            "render" => {
                let p = ctx.project()?;
                let fmt = s("format").unwrap_or_else(|| "outline".into());
                if running.is_some() {
                    let t = api("GET", &format!("/tree?name={}", enc(&name)), json!({}), 10)?;
                    if fmt == "json" {
                        return Ok(text(serde_json::to_string_pretty(&json!({"ok": t["ok"], "error": t["error"], "logs": t["logs"], "roots": t["roots"]})).unwrap()));
                    }
                    Ok(text(summarize(&name, t["ok"].as_bool().unwrap_or(false), t["error"].as_str(), &t["logs"], t["outline"].as_str().unwrap_or(""), t["yielded"].as_bool().unwrap_or(false))))
                } else {
                    let (ok, err, logs, outline, y, roots) = render_headless(&p, &name)?;
                    if fmt == "json" {
                        return Ok(text(serde_json::to_string_pretty(&json!({"ok": ok, "error": err, "logs": logs, "roots": roots})).unwrap()));
                    }
                    Ok(text(summarize(&name, ok, err.as_deref(), &logs, &outline, y)))
                }
            }
            "show_ui" => {
                need_app()?;
                let route = if a["exclusive"].as_bool().unwrap_or(false) { "/only" } else { "/show" };
                api("POST", route, json!({"name": name}), 10)?;
                Ok(text(format!("{name} shown.")))
            }
            "hide_ui" => {
                need_app()?;
                api("POST", "/hide", json!({"name": name}), 10)?;
                Ok(text(format!("{name} closed.")))
            }
            "show_all" => {
                need_app()?;
                api("POST", "/show_all", json!({}), 10)?;
                Ok(text("All UIs are shown."))
            }
            "hide_all" => {
                need_app()?;
                api("POST", "/hide_all", json!({}), 10)?;
                Ok(text("All UIs are closed."))
            }
            "set_device" => {
                need_app()?;
                let d = s("device").ok_or("missing device")?;
                let st = api("POST", "/device", json!({"device": d}), 30)?;
                Ok(text(format!("Device: {}", st["device"]["label"].as_str().unwrap_or(&d))))
            }
            "get_layout" => {
                need_app()?;
                let v = api("GET", &format!("/layout?name={}", enc(&name)), json!({}), 20)?;
                let mut out = format!("Device {}×{} (Roblox top bar: 58 px at the top unless IgnoreGuiInset)\n", v["device"]["w"], v["device"]["h"]);
                for n in v["nodes"].as_array().cloned().unwrap_or_default() {
                    let mut flags = vec![];
                    if !n["visible"].as_bool().unwrap_or(true) { flags.push("invisible"); }
                    if n["textOverflow"].as_bool() == Some(true) { flags.push("TEXT OVERFLOWS"); }
                    if n["offscreen"].as_bool() == Some(true) { flags.push("OFF-SCREEN"); } else if n["clipped"].as_bool() == Some(true) { flags.push("crosses screen edge"); }
                    out.push_str(&format!(
                        "{} [{}] x={} y={} {}×{}{}{}\n",
                        n["path"].as_str().unwrap_or(""), n["class"].as_str().unwrap_or(""), n["x"], n["y"], n["w"], n["h"],
                        n["text"].as_str().map(|t| format!(" text={:?} size={}", t.chars().take(40).collect::<String>(), n["fontSize"])).unwrap_or_default(),
                        if flags.is_empty() { String::new() } else { format!("  ⚠ {}", flags.join(", ")) }
                    ));
                }
                Ok(text(out))
            }
            "screenshot" => {
                need_app()?;
                let scope = s("scope").unwrap_or_else(|| "viewport".into());
                let q = if name.is_empty() { format!("/screenshot?scope={scope}") } else { format!("/screenshot?scope={scope}&name={}", enc(&name)) };
                let v = api("GET", &q, json!({}), 25)?;
                let data = v["png_base64"].as_str().ok_or("empty capture")?;
                Ok(json!({"content": [
                    {"type": "image", "data": data, "mimeType": "image/png"},
                    {"type": "text", "text": format!("Capture {}×{} px", v["width"], v["height"])}
                ]}))
            }
            "click" | "type_text" => {
                need_app()?;
                let node = s("node").ok_or("missing node")?;
                let mut body = json!({"name": name, "node": node});
                if let Some(e) = s("event") { body["event"] = json!(e); }
                if tool == "type_text" {
                    body["text"] = json!(s("text").unwrap_or_default());
                    body["enter"] = json!(a["enter"].as_bool().unwrap_or(true));
                }
                let v = api("POST", "/fire", body, 15)?;
                Ok(text(format!(
                    "{} handler(s) fired.\n{}",
                    v["fired"],
                    summarize(&name, v["ok"].as_bool().unwrap_or(false), v["error"].as_str(), &v["logs"], v["outline"].as_str().unwrap_or(""), false)
                )))
            }
            "reset_ui" => {
                need_app()?;
                api("POST", "/reload", json!({"name": name}), 20)?;
                Ok(text(format!("{name} reloaded (state reset).")))
            }
            "launch_app" => {
                if let Some(st) = &running {
                    if let Some(p) = s("project") {
                        api("POST", "/open_project", json!({"path": p}), 30)?;
                        return Ok(text(format!("App already open; switched project to {p}.")));
                    }
                    return Ok(text(format!("App already open on {}.", st["root"].as_str().unwrap_or(""))));
                }
                let proj = match s("project") {
                    Some(p) => PathBuf::from(p),
                    None => ctx.project().map(|p| p.root)?,
                };
                if !proj.is_dir() {
                    return Err(format!("folder not found: {}", proj.display()));
                }
                ctx.project = Some(proj.clone());
                let exe = std::env::current_exe().map_err(|e| e.to_string())?;
                let app = exe.with_file_name(if cfg!(windows) { "luauui.exe" } else { "luauui" });
                let mut cmd = std::process::Command::new(&app);
                cmd.arg(&proj).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::null());
                #[cfg(windows)]
                {
                    use std::os::windows::process::CommandExt;
                    cmd.creation_flags(0x0000_0008 | 0x0000_0200); // DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
                    // Do not let the app inherit our stdio pipes (the MCP client would wait on them).
                    unsafe {
                        use windows_sys::Win32::Foundation::{SetHandleInformation, HANDLE_FLAG_INHERIT};
                        use windows_sys::Win32::System::Console::{GetStdHandle, STD_ERROR_HANDLE, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE};
                        for h in [STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE] {
                            let handle = GetStdHandle(h);
                            if !handle.is_null() {
                                SetHandleInformation(handle, HANDLE_FLAG_INHERIT, 0);
                            }
                        }
                    }
                }
                cmd.spawn().map_err(|e| format!("launching {}: {e}", app.display()))?;
                if wait_for_app(20) {
                    Ok(text(format!("LuauUI Studio opened on {}.", slash(&proj))))
                } else {
                    Err("the app is not responding after 20 s".into())
                }
            }
            "open_project" => {
                let p = s("path").ok_or("missing path")?;
                let pb = PathBuf::from(&p);
                if !pb.is_dir() {
                    return Err(format!("folder not found: {p}"));
                }
                ctx.project = Some(pb);
                if running.is_some() {
                    api("POST", "/open_project", json!({"path": p}), 30)?;
                }
                Ok(text(format!("Project: {p}")))
            }
            "init_project" => {
                let p = PathBuf::from(s("path").ok_or("missing path")?);
                let ui = p.join("ui");
                std::fs::create_dir_all(&ui).map_err(|e| e.to_string())?;
                let hello = ui.join("Hello.luau");
                if !hello.exists() {
                    std::fs::write(&hello, project::template_component("Hello")).map_err(|e| e.to_string())?;
                }
                let cfg = p.join("luauui.json");
                if !cfg.exists() {
                    std::fs::write(&cfg, "{\n  \"uiDir\": \"ui\"\n}\n").map_err(|e| e.to_string())?;
                }
                ctx.project = Some(p.clone());
                Ok(text(format!("Project created: {} (ui/Hello.luau)", slash(&p))))
            }
            other => Err(format!("unknown tool: {other}")),
        }
    })();
    match r {
        Ok(v) => v,
        Err(e) => fail(e),
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut project: Option<PathBuf> = std::env::var("LUAUUI_PROJECT").ok().map(PathBuf::from);
    while let Some(a) = args.next() {
        if a == "--project" {
            project = args.next().map(PathBuf::from);
        } else if !a.starts_with('-') {
            project = Some(PathBuf::from(a));
        }
    }
    let mut ctx = Ctx { project };
    let stdin = std::io::stdin();
    let mut stdout = std::io::stdout();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        if line.trim().is_empty() {
            continue;
        }
        let line = line.trim_start_matches('\u{feff}');
        let Ok(msg) = serde_json::from_str::<Json>(line) else {
            let _ = writeln!(stdout, "{}", json!({"jsonrpc": "2.0", "id": null, "error": {"code": -32700, "message": "parse error"}}));
            let _ = stdout.flush();
            continue;
        };
        let id = msg.get("id").cloned();
        let method = msg["method"].as_str().unwrap_or("");
        let result: Option<Result<Json, (i64, String)>> = match method {
            "initialize" => {
                let pv = msg["params"]["protocolVersion"].as_str().unwrap_or("2025-06-18").to_string();
                Some(Ok(json!({
                    "protocolVersion": pv,
                    "capabilities": {"tools": {"listChanged": false}},
                    "serverInfo": {"name": "luauui", "version": env!("CARGO_PKG_VERSION")},
                    "instructions": "LuauUI: live preview of Roblox interfaces written in Luau. Suggested flow: status → (launch_app if needed) → api_reference (once) → write_ui (returns tree + errors + overflows) → screenshot to see the result → click/type_text to test interactivity. UIs are ui/<Name>.luau files; shared modules go in ui/_shared/."
                })))
            }
            "ping" => Some(Ok(json!({}))),
            "tools/list" => Some(Ok(json!({"tools": tools()}))),
            "tools/call" => {
                let name = msg["params"]["name"].as_str().unwrap_or("").to_string();
                let args = msg["params"]["arguments"].clone();
                Some(Ok(call(&mut ctx, &name, &args)))
            }
            "resources/list" => Some(Ok(json!({"resources": []}))),
            "prompts/list" => Some(Ok(json!({"prompts": []}))),
            m if m.starts_with("notifications/") => None,
            _ => Some(Err((-32601, format!("unknown method: {method}")))),
        };
        if let (Some(id), Some(res)) = (id, result) {
            let out = match res {
                Ok(r) => json!({"jsonrpc": "2.0", "id": id, "result": r}),
                Err((code, m)) => json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": m}}),
            };
            let _ = writeln!(stdout, "{out}");
            let _ = stdout.flush();
        }
    }
}
