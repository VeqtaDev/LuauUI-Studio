#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
//! LuauUI Studio: native window (tao + wry/WebView2) that runs Luau UI files
//! in Luau VMs, hot reloads them on save and exposes a local control API
//! (127.0.0.1:47821) used by the MCP server.

use luauui::project::{self, Device, Project, UiEntry, API_PORT, DEVICES};
use luauui::runtime::{self, slash, LogLine, RenderResult, UiSession};
use notify::{RecursiveMode, Watcher};
use serde_json::{json, Value as Json};
use std::borrow::Cow;
use std::collections::{BTreeSet, HashMap};
use std::path::{Path, PathBuf};
use std::sync::mpsc::{self, Sender};
use std::time::{Duration, Instant};
use tao::dpi::LogicalSize;
use tao::event::{Event, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoopBuilder, EventLoopProxy};
use tao::window::{Window, WindowBuilder};
use wry::http::{header::CONTENT_TYPE, Response};
use wry::{WebView, WebViewBuilder};

const INDEX_HTML: &str = include_str!("../ui/index.html");

type Reply = Sender<(u16, String)>;

enum UserEvent {
    Ipc(String),
    FsChanged(Vec<PathBuf>),
    Api { method: String, path: String, query: HashMap<String, String>, body: String, reply: Reply },
}

enum Pending {
    Layout(Reply),
    Screenshot(Reply),
}

struct UiState {
    entry: UiEntry,
    session: Option<UiSession>,
    result: RenderResult,
}

struct App {
    project: Project,
    uis: Vec<UiState>,
    visible: BTreeSet<String>,
    selected: Option<String>,
    device: Device,
    live: bool,
    logs: Vec<Json>,
    last_reload: Option<Json>,
    pending: HashMap<u64, Pending>,
    next_req: u64,
    queued_changes: bool,
    watcher: Option<notify::RecommendedWatcher>,
    proxy: EventLoopProxy<UserEvent>,
}

impl App {
    fn new(project: Project, proxy: EventLoopProxy<UserEvent>) -> Self {
        let mut app = App {
            project,
            uis: vec![],
            visible: BTreeSet::new(),
            selected: None,
            device: DEVICES[0],
            live: true,
            logs: vec![],
            last_reload: None,
            pending: HashMap::new(),
            next_req: 1,
            queued_changes: false,
            watcher: None,
            proxy,
        };
        app.load_state();
        app.rescan_and_render_all();
        app.watch();
        app
    }

    fn load_state(&mut self) {
        let Ok(s) = std::fs::read_to_string(self.project.state_file()) else {
            return;
        };
        let Ok(v) = serde_json::from_str::<Json>(&s) else { return };
        if let Some(arr) = v["visible"].as_array() {
            self.visible = arr.iter().filter_map(|x| x.as_str().map(String::from)).collect();
        }
        self.selected = v["selected"].as_str().map(String::from);
        if let Some(d) = v["device"].as_str() {
            self.device = project::device(d);
        }
    }

    fn save_state(&self) {
        let f = self.project.state_file();
        if let Some(dir) = f.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let v = json!({
            "visible": self.visible.iter().collect::<Vec<_>>(),
            "selected": self.selected,
            "device": self.device.id,
        });
        let _ = std::fs::write(f, serde_json::to_string_pretty(&v).unwrap_or_default());
    }

    fn watch(&mut self) {
        let (tx, rx) = mpsc::channel::<PathBuf>();
        let watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
            if let Ok(ev) = res {
                if matches!(ev.kind, notify::EventKind::Access(_)) {
                    return;
                }
                for p in ev.paths {
                    let _ = tx.send(p);
                }
            }
        });
        let Ok(mut watcher) = watcher else { return };
        if watcher.watch(&self.project.root, RecursiveMode::Recursive).is_err() {
            return;
        }
        let proxy = self.proxy.clone();
        std::thread::spawn(move || {
            // debounce: collect paths until 35 ms of silence
            while let Ok(first) = rx.recv() {
                let mut batch = vec![first];
                while let Ok(p) = rx.recv_timeout(Duration::from_millis(35)) {
                    batch.push(p);
                }
                let relevant: Vec<PathBuf> = batch
                    .into_iter()
                    .filter(|p| {
                        let s = slash(p);
                        !s.contains("/.luauui/")
                            && !s.contains("/.git/")
                            && matches!(
                                p.extension().and_then(|e| e.to_str()),
                                Some("luau" | "lua" | "json") | None
                            )
                    })
                    .collect();
                if !relevant.is_empty() && proxy.send_event(UserEvent::FsChanged(relevant)).is_err() {
                    break;
                }
            }
        });
        self.watcher = Some(watcher);
    }

    fn push_logs(&mut self, ui: &str, logs: &[LogLine], error: &Option<String>) {
        for l in logs {
            self.logs.push(json!({"ui": ui, "kind": l.kind, "text": l.text}));
        }
        if let Some(e) = error {
            self.logs.push(json!({"ui": ui, "kind": "error", "text": e}));
        }
        let n = self.logs.len();
        if n > 400 {
            self.logs.drain(0..n - 400);
        }
    }

    fn render_ui(&mut self, idx: usize) {
        let dev = (self.device.w, self.device.h);
        let entry = self.uis[idx].entry.clone();
        let (session, result) = runtime::run_file(&self.project.root, &entry.path, dev);
        self.push_logs(&entry.name, &result.logs, &result.error);
        self.uis[idx].session = session;
        self.uis[idx].result = result;
    }

    fn rescan_and_render_all(&mut self) {
        let t0 = Instant::now();
        let entries = self.project.find_uis();
        self.uis = entries
            .into_iter()
            .map(|entry| UiState { entry, session: None, result: RenderResult::default() })
            .collect();
        for i in 0..self.uis.len() {
            self.render_ui(i);
        }
        let names: BTreeSet<String> = self.uis.iter().map(|u| u.entry.name.clone()).collect();
        self.visible.retain(|n| names.contains(n));
        if self.selected.as_ref().map(|s| !names.contains(s)).unwrap_or(true) {
            self.selected = self.uis.first().map(|u| u.entry.name.clone());
        }
        self.last_reload = Some(json!({
            "file": "project",
            "ms": round1(t0.elapsed().as_secs_f64() * 1000.0),
            "at": now_ms(),
        }));
    }

    fn idx(&self, name: &str) -> Option<usize> {
        self.uis.iter().position(|u| u.entry.name == name)
    }

    fn on_fs_change(&mut self, paths: Vec<PathBuf>) {
        if !self.live {
            self.queued_changes = true;
            return;
        }
        let t0 = Instant::now();
        let known: Vec<PathBuf> = self.uis.iter().map(|u| u.entry.path.clone()).collect();
        let current = self.project.find_uis();
        let structure_changed = current.len() != known.len()
            || current.iter().zip(known.iter()).any(|(a, b)| a.path != *b);
        let changed_file = paths
            .iter()
            .find(|p| p.extension().map(|e| e == "luau" || e == "lua").unwrap_or(false))
            .cloned();
        if structure_changed {
            self.rescan_and_render_all();
        } else {
            // a listed UI file changed: re-render it; a shared module changed: re-render all
            let direct: Vec<usize> = paths
                .iter()
                .filter_map(|p| {
                    self.uis.iter().position(|u| same_path(&u.entry.path, p))
                })
                .collect();
            let only_direct = !direct.is_empty()
                && paths
                    .iter()
                    .filter(|p| p.extension().map(|e| e == "luau" || e == "lua").unwrap_or(false))
                    .all(|p| self.uis.iter().any(|u| same_path(&u.entry.path, p)));
            if only_direct {
                for i in direct {
                    self.render_ui(i);
                }
            } else {
                for i in 0..self.uis.len() {
                    self.render_ui(i);
                }
            }
        }
        let file = changed_file
            .as_ref()
            .and_then(|p| p.file_name())
            .map(|f| f.to_string_lossy().to_string())
            .unwrap_or_else(|| "project".into());
        self.last_reload = Some(json!({
            "file": file,
            "ms": round1(t0.elapsed().as_secs_f64() * 1000.0),
            "at": now_ms(),
        }));
    }

    fn fire(&mut self, name: &str, calls: &[Json]) -> Result<(), String> {
        let i = self.idx(name).ok_or("unknown UI")?;
        let t0 = Instant::now();
        {
            let Some(sess) = self.uis[i].session.as_ref() else {
                return Err("UI not loaded".into());
            };
            for c in calls {
                let id = c["id"].as_i64().unwrap_or(0);
                sess.fire(id, &c["payload"])?;
            }
        }
        let sess = self.uis[i].session.as_ref().unwrap();
        let mut res = runtime::rerender(sess);
        res.ms = t0.elapsed().as_secs_f64() * 1000.0;
        let logs = res.logs.clone();
        let err = res.error.clone();
        self.uis[i].result = res;
        self.push_logs(name, &logs, &err);
        Ok(())
    }

    fn state_json(&self, with_trees: bool) -> Json {
        let uis: Vec<Json> = self
            .uis
            .iter()
            .map(|u| {
                json!({
                    "name": u.entry.name,
                    "path": slash(u.entry.path.strip_prefix(&self.project.root).unwrap_or(&u.entry.path)),
                    "visible": self.visible.contains(&u.entry.name),
                    "ok": u.result.ok,
                    "error": u.result.error,
                    "ms": round1(u.result.ms),
                    "yielded": u.result.yielded,
                })
            })
            .collect();
        let mut v = json!({
            "project": self.project.name(),
            "root": slash(&self.project.root),
            "uiDir": slash(self.project.ui_dir.strip_prefix(&self.project.root).unwrap_or(&self.project.ui_dir)),
            "uis": uis,
            "selected": self.selected,
            "device": self.device,
            "devices": DEVICES,
            "live": self.live,
            "reload": self.last_reload,
            "port": API_PORT,
        });
        if with_trees {
            let mut trees = serde_json::Map::new();
            for u in &self.uis {
                let show = self.visible.contains(&u.entry.name) || self.selected.as_deref() == Some(&u.entry.name);
                if show {
                    trees.insert(u.entry.name.clone(), u.result.roots.clone());
                }
            }
            v["trees"] = Json::Object(trees);
            v["logs"] = Json::Array(self.logs.iter().rev().take(200).rev().cloned().collect());
            if let Some(sel) = &self.selected {
                if let Some(i) = self.idx(sel) {
                    v["source"] = Json::String(std::fs::read_to_string(&self.uis[i].entry.path).unwrap_or_default());
                }
            }
        }
        v
    }

    fn push(&self, wv: &WebView) {
        let s = self.state_json(true).to_string();
        let _ = wv.evaluate_script(&format!("window.__luauui && window.__luauui.receive({s})"));
    }

    fn create_ui(&mut self, name: &str, kind: &str, source: Option<&str>) -> Result<PathBuf, String> {
        if !project::valid_name(name) {
            return Err("invalid name (letters, digits, _ - /)".into());
        }
        let path = self.project.ui_path(name).ok_or("invalid name")?;
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
        }
        let src = match source {
            Some(s) => s.to_string(),
            None => {
                if path.exists() {
                    return Err("this file already exists".into());
                }
                if kind == "instance" {
                    project::template_instance(name)
                } else {
                    project::template_component(name)
                }
            }
        };
        std::fs::write(&path, src).map_err(|e| e.to_string())?;
        Ok(path)
    }

    fn set_project(&mut self, root: &Path) -> Result<(), String> {
        if !root.is_dir() {
            return Err(format!("folder not found: {}", root.display()));
        }
        self.save_state();
        self.watcher = None;
        self.project = Project::open(root);
        self.visible.clear();
        self.selected = None;
        self.logs.clear();
        self.load_state();
        self.rescan_and_render_all();
        self.watch();
        Ok(())
    }
}

fn same_path(a: &Path, b: &Path) -> bool {
    slash(a).to_lowercase() == slash(b).to_lowercase()
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

fn now_ms() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

fn open_in_editor(path: &Path) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        let ok = std::process::Command::new("cmd")
            .args(["/C", "code", "-g"])
            .arg(path)
            .creation_flags(CREATE_NO_WINDOW)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            return;
        }
    }
    let _ = open::that_detached(path);
}

// ---------------------------------------------------------------------------
// HTTP control API
// ---------------------------------------------------------------------------

fn start_api(proxy: EventLoopProxy<UserEvent>) {
    std::thread::spawn(move || {
        let Ok(server) = tiny_http::Server::http(("127.0.0.1", API_PORT)) else {
            return;
        };
        for mut req in server.incoming_requests() {
            let proxy = proxy.clone();
            let mut body = String::new();
            let _ = req.as_reader().read_to_string(&mut body);
            let url = req.url().to_string();
            let (path, qs) = url.split_once('?').unwrap_or((&url, ""));
            let query: HashMap<String, String> = qs
                .split('&')
                .filter_map(|kv| kv.split_once('='))
                .map(|(k, v)| (k.to_string(), url_decode(v)))
                .collect();
            let (tx, rx) = mpsc::channel();
            let ev = UserEvent::Api {
                method: req.method().to_string(),
                path: path.to_string(),
                query,
                body,
                reply: tx,
            };
            std::thread::spawn(move || {
                let (code, text) = if proxy.send_event(ev).is_ok() {
                    rx.recv_timeout(Duration::from_secs(20))
                        .unwrap_or((504, json!({"error": "timeout"}).to_string()))
                } else {
                    (503, json!({"error": "app closed"}).to_string())
                };
                let header = tiny_http::Header::from_bytes(&b"Content-Type"[..], &b"application/json; charset=utf-8"[..]).unwrap();
                let _ = req.respond(tiny_http::Response::from_string(text).with_status_code(code).with_header(header));
            });
        }
    });
}

fn url_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < bytes.len() => {
                if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                    out.push(v);
                    i += 2;
                } else {
                    out.push(b'%');
                }
            }
            b => out.push(b),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn ok(v: Json) -> (u16, String) {
    (200, v.to_string())
}
fn err(code: u16, msg: impl Into<String>) -> (u16, String) {
    (code, json!({"error": msg.into()}).to_string())
}

/// Handles an API call. Returns None when the reply is deferred (needs the page).
fn handle_api(
    app: &mut App,
    wv: &WebView,
    window: &Window,
    method: &str,
    path: &str,
    query: &HashMap<String, String>,
    body: &str,
    reply: Reply,
) {
    let b: Json = serde_json::from_str(body).unwrap_or(Json::Null);
    let arg = |k: &str| -> Option<String> {
        b[k].as_str().map(String::from).or_else(|| query.get(k).cloned())
    };
    let name = arg("name");
    let mut changed = false;
    let resp: (u16, String) = match (method, path) {
        ("GET", "/state") => ok(app.state_json(false)),
        ("GET", "/tree") => match name.as_deref().and_then(|n| app.idx(n)) {
            Some(i) => {
                let u = &app.uis[i];
                ok(json!({
                    "name": u.entry.name,
                    "ok": u.result.ok,
                    "error": u.result.error,
                    "logs": u.result.logs,
                    "yielded": u.result.yielded,
                    "ms": round1(u.result.ms),
                    "roots": u.result.roots,
                    "outline": project::outline(&u.result.roots),
                }))
            }
            None => err(404, "unknown UI"),
        },
        ("GET", "/logs") => ok(json!({"logs": app.logs})),
        ("POST", "/show") | ("POST", "/hide") | ("POST", "/only") | ("POST", "/select") => {
            match name.clone().filter(|n| app.idx(n).is_some()) {
                Some(n) => {
                    match path {
                        "/show" => {
                            app.visible.insert(n.clone());
                            app.selected = Some(n);
                        }
                        "/hide" => {
                            app.visible.remove(&n);
                        }
                        "/only" => {
                            app.visible.clear();
                            app.visible.insert(n.clone());
                            app.selected = Some(n);
                        }
                        _ => app.selected = Some(n),
                    }
                    changed = true;
                    ok(app.state_json(false))
                }
                None => err(404, "unknown UI"),
            }
        }
        ("POST", "/show_all") => {
            app.visible = app.uis.iter().map(|u| u.entry.name.clone()).collect();
            changed = true;
            ok(app.state_json(false))
        }
        ("POST", "/hide_all") => {
            app.visible.clear();
            changed = true;
            ok(app.state_json(false))
        }
        ("POST", "/device") => match arg("device") {
            Some(d) if DEVICES.iter().any(|x| x.id == d) => {
                app.device = project::device(&d);
                app.rescan_and_render_all();
                changed = true;
                ok(app.state_json(false))
            }
            _ => err(400, format!("unknown device; choices: {}", DEVICES.iter().map(|d| d.id).collect::<Vec<_>>().join(", "))),
        },
        ("POST", "/reload") => {
            if let Some(i) = name.as_deref().and_then(|n| app.idx(n)) {
                app.render_ui(i);
            } else {
                app.rescan_and_render_all();
            }
            changed = true;
            ok(app.state_json(false))
        }
        ("POST", "/open_project") => match arg("path") {
            Some(p) => match app.set_project(Path::new(&p)) {
                Ok(()) => {
                    changed = true;
                    ok(app.state_json(false))
                }
                Err(e) => err(400, e),
            },
            None => err(400, "missing path"),
        },
        ("POST", "/fire") => {
            // body: {name, node: "Path/To/Node", event: "Activated", text?, enter?}
            let n = name.clone().unwrap_or_default();
            match app.idx(&n) {
                None => err(404, "unknown UI"),
                Some(i) => {
                    let node_path = arg("node").unwrap_or_default();
                    let roots = app.uis[i].result.roots.clone();
                    match project::find_node(&roots, &node_path) {
                        None => err(404, format!("node not found: {node_path}")),
                        Some(node) => {
                            let ev = node["ev"].as_object().cloned().unwrap_or_default();
                            let wanted: Vec<String> = match arg("event") {
                                Some(e) => vec![e],
                                None => {
                                    if b.get("text").is_some() {
                                        vec!["Change:Text".into(), "Changed".into(), "FocusLost".into()]
                                    } else {
                                        vec!["Activated".into(), "MouseButton1Click".into(), "MouseButton1Down".into(), "MouseButton1Up".into()]
                                    }
                                }
                            };
                            let mut payload = json!({});
                            if let Some(t) = b.get("text") {
                                payload["text"] = t.clone();
                                payload["enter"] = b.get("enter").cloned().unwrap_or(Json::Bool(true));
                            }
                            let calls: Vec<Json> = wanted
                                .iter()
                                .filter_map(|e| ev.get(e).map(|id| json!({"id": id, "payload": payload})))
                                .collect();
                            if calls.is_empty() {
                                err(400, format!(
                                    "no {:?} handler on this node (events: {:?})",
                                    wanted,
                                    ev.keys().collect::<Vec<_>>()
                                ))
                            } else {
                                match app.fire(&n, &calls) {
                                    Ok(()) => {
                                        changed = true;
                                        let u = &app.uis[i];
                                        ok(json!({
                                            "fired": calls.len(),
                                            "ok": u.result.ok,
                                            "error": u.result.error,
                                            "logs": u.result.logs,
                                            "outline": project::outline(&u.result.roots),
                                        }))
                                    }
                                    Err(e) => err(500, e),
                                }
                            }
                        }
                    }
                }
            }
        }
        ("GET", "/layout") | ("GET", "/screenshot") => {
            if let Some(n) = name.as_deref() {
                if app.idx(n).is_none() {
                    let _ = reply.send(err(404, "unknown UI"));
                    return;
                }
                if path == "/layout" && !app.visible.contains(n) {
                    app.visible.insert(n.to_string());
                    app.selected = Some(n.to_string());
                    app.save_state();
                    app.push(wv);
                }
            }
            if path == "/screenshot" {
                if window.is_minimized() {
                    window.set_minimized(false);
                }
                if let Some(n) = name.as_deref() {
                    app.visible.insert(n.to_string());
                    app.selected = Some(n.to_string());
                    app.push(wv);
                }
            }
            let id = app.next_req;
            app.next_req += 1;
            let scope = arg("scope").unwrap_or_else(|| "viewport".into());
            if path == "/layout" {
                app.pending.insert(id, Pending::Layout(reply));
                let _ = wv.evaluate_script(&format!(
                    "window.__luauui && window.__luauui.layout({id}, {})",
                    serde_json::to_string(&name).unwrap()
                ));
            } else {
                app.pending.insert(id, Pending::Screenshot(reply));
                let _ = wv.evaluate_script(&format!(
                    "window.__luauui && window.__luauui.rect({id}, {})",
                    serde_json::to_string(&scope).unwrap()
                ));
            }
            return;
        }
        _ => err(404, "unknown route"),
    };
    if changed {
        app.save_state();
        app.push(wv);
    }
    let _ = reply.send(resp);
}

// ---------------------------------------------------------------------------
// Screenshot (Windows: PrintWindow with full content, fallback to screen copy)
// ---------------------------------------------------------------------------

#[cfg(windows)]
fn capture(window: &Window, rect: (i32, i32, i32, i32)) -> Result<Vec<u8>, String> {
    use tao::platform::windows::WindowExtWindows;
    use windows_sys::Win32::Foundation::{HWND, POINT, RECT};
    use windows_sys::Win32::Graphics::Gdi::*;
    use windows_sys::Win32::Storage::Xps::PrintWindow;
    use windows_sys::Win32::UI::WindowsAndMessaging::GetClientRect;

    unsafe {
        let hwnd = window.hwnd() as HWND;
        let mut rc: RECT = std::mem::zeroed();
        GetClientRect(hwnd, &mut rc);
        let (w, h) = (rc.right - rc.left, rc.bottom - rc.top);
        if w <= 0 || h <= 0 {
            return Err("window is minimized".into());
        }
        let grab = |from_screen: bool| -> Vec<u8> {
            let hdc = GetDC(hwnd);
            let mem = CreateCompatibleDC(hdc);
            let bmp = CreateCompatibleBitmap(hdc, w, h);
            let old = SelectObject(mem, bmp);
            if from_screen {
                let screen = GetDC(std::ptr::null_mut());
                let mut pt = POINT { x: 0, y: 0 };
                ClientToScreen(hwnd, &mut pt);
                BitBlt(mem, 0, 0, w, h, screen, pt.x, pt.y, SRCCOPY);
                ReleaseDC(std::ptr::null_mut(), screen);
            } else {
                PrintWindow(hwnd, mem, 1 | 2); // PW_CLIENTONLY | PW_RENDERFULLCONTENT
            }
            let mut bmi: BITMAPINFO = std::mem::zeroed();
            bmi.bmiHeader.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
            bmi.bmiHeader.biWidth = w;
            bmi.bmiHeader.biHeight = -h;
            bmi.bmiHeader.biPlanes = 1;
            bmi.bmiHeader.biBitCount = 32;
            bmi.bmiHeader.biCompression = BI_RGB;
            let mut buf = vec![0u8; (w * h * 4) as usize];
            GetDIBits(mem, bmp, 0, h as u32, buf.as_mut_ptr() as *mut _, &mut bmi, DIB_RGB_COLORS);
            SelectObject(mem, old);
            DeleteObject(bmp);
            DeleteDC(mem);
            ReleaseDC(hwnd, hdc);
            buf
        };
        let mut buf = grab(false);
        let blank = buf.chunks(4).step_by(97).all(|p| p[0] == 0 && p[1] == 0 && p[2] == 0);
        if blank {
            buf = grab(true);
        }
        let (x, y, cw, ch) = rect;
        let x = x.clamp(0, w - 1);
        let y = y.clamp(0, h - 1);
        let cw = cw.clamp(1, w - x);
        let ch = ch.clamp(1, h - y);
        let mut rgba = Vec::with_capacity((cw * ch * 4) as usize);
        for row in y..y + ch {
            let start = ((row * w + x) * 4) as usize;
            for px in buf[start..start + (cw * 4) as usize].chunks(4) {
                rgba.extend_from_slice(&[px[2], px[1], px[0], 255]);
            }
        }
        let mut out = Vec::new();
        {
            let mut enc = png::Encoder::new(&mut out, cw as u32, ch as u32);
            enc.set_color(png::ColorType::Rgba);
            enc.set_depth(png::BitDepth::Eight);
            let mut wr = enc.write_header().map_err(|e| e.to_string())?;
            wr.write_image_data(&rgba).map_err(|e| e.to_string())?;
        }
        Ok(out)
    }
}

#[cfg(not(windows))]
fn capture(_window: &Window, _rect: (i32, i32, i32, i32)) -> Result<Vec<u8>, String> {
    Err("capture is only available on Windows".into())
}

// ---------------------------------------------------------------------------
// Roblox image proxy (rbxassetid -> thumbnail PNG), cached on disk
// ---------------------------------------------------------------------------

fn cache_dir() -> PathBuf {
    let base = std::env::var("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(|_| std::env::temp_dir());
    base.join("LuauUI").join("cache")
}

fn fetch_rbx_image(id: &str) -> Option<Vec<u8>> {
    if !id.chars().all(|c| c.is_ascii_digit()) || id.is_empty() {
        return None;
    }
    let dir = cache_dir();
    let file = dir.join(format!("{id}.png"));
    if let Ok(b) = std::fs::read(&file) {
        return Some(b);
    }
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(8)).build();
    let meta: Json = agent
        .get(&format!(
            "https://thumbnails.roblox.com/v1/assets?assetIds={id}&returnPolicy=PlaceHolder&size=420x420&format=Png&isCircular=false"
        ))
        .call()
        .ok()?
        .into_string()
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())?;
    let url = meta["data"][0]["imageUrl"].as_str()?.to_string();
    let resp = agent.get(&url).call().ok()?;
    let mut bytes = Vec::new();
    std::io::Read::read_to_end(&mut resp.into_reader(), &mut bytes).ok()?;
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(&file, &bytes);
    Some(bytes)
}

fn mime_for(p: &str) -> &'static str {
    match p.rsplit('.').next().unwrap_or("").to_lowercase().as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        _ => "application/octet-stream",
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    let root = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    let project = Project::open(&root);
    if !project.ui_dir.exists() {
        let _ = std::fs::create_dir_all(&project.ui_dir);
    }

    let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();
    let proxy = event_loop.create_proxy();

    let window = WindowBuilder::new()
        .with_title("LuauUI Studio")
        .with_inner_size(LogicalSize::new(1440.0, 900.0))
        .with_min_inner_size(LogicalSize::new(980.0, 640.0))
        .with_decorations(false)
        .with_transparent(false)
        .build(&event_loop)
        .expect("window");

    let ipc_proxy = proxy.clone();
    let root_for_assets = std::sync::Arc::new(std::sync::Mutex::new(project.root.clone()));
    let assets_root = root_for_assets.clone();

    let data_dir = cache_dir().parent().map(|p| p.join("webview")).unwrap_or_else(cache_dir);
    let mut ctx = wry::WebContext::new(Some(data_dir));

    let webview = WebViewBuilder::new_with_web_context(&mut ctx)
        .with_background_color((0, 0, 0, 255))
        .with_asynchronous_custom_protocol("luauui".into(), move |_id, request, responder| {
            let path = request.uri().path().to_string();
            let assets_root = assets_root.clone();
            std::thread::spawn(move || {
                let send = |status: u16, mime: &str, body: Vec<u8>| {
                    let resp = Response::builder()
                        .status(status)
                        .header(CONTENT_TYPE, mime)
                        .header("Access-Control-Allow-Origin", "*")
                        .header("Cache-Control", "no-cache")
                        .body(Cow::Owned(body))
                        .unwrap();
                    responder.respond(resp);
                };
                if path == "/" || path == "/index.html" {
                    send(200, "text/html; charset=utf-8", INDEX_HTML.as_bytes().to_vec());
                } else if let Some(id) = path.strip_prefix("/rbx/") {
                    match fetch_rbx_image(id) {
                        Some(b) => send(200, "image/png", b),
                        None => send(404, "text/plain", b"not found".to_vec()),
                    }
                } else if let Some(rel) = path.strip_prefix("/file/") {
                    let rel = url_decode(rel);
                    let root = assets_root.lock().unwrap().clone();
                    let p = runtime::normalize(&root.join(&rel));
                    if slash(&p).to_lowercase().starts_with(&slash(&root).to_lowercase()) {
                        match std::fs::read(&p) {
                            Ok(b) => send(200, mime_for(&rel), b),
                            Err(_) => send(404, "text/plain", b"not found".to_vec()),
                        }
                    } else {
                        send(403, "text/plain", b"forbidden".to_vec());
                    }
                } else {
                    send(404, "text/plain", b"not found".to_vec());
                }
            });
        })
        .with_url("luauui://localhost/")
        .with_ipc_handler(move |req| {
            let _ = ipc_proxy.send_event(UserEvent::Ipc(req.body().clone()));
        })
        .with_devtools(cfg!(debug_assertions))
        .build(&window)
        .expect("webview");

    let mut app = App::new(project, proxy.clone());
    start_api(proxy.clone());

    event_loop.run(move |event, _target, control_flow| {
        *control_flow = ControlFlow::Wait;
        let _keep = &ctx;
        match event {
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                app.save_state();
                *control_flow = ControlFlow::Exit;
            }
            Event::UserEvent(UserEvent::FsChanged(paths)) => {
                app.on_fs_change(paths);
                app.push(&webview);
            }
            Event::UserEvent(UserEvent::Api { method, path, query, body, reply }) => {
                handle_api(&mut app, &webview, &window, &method, &path, &query, &body, reply);
                *root_for_assets.lock().unwrap() = app.project.root.clone();
            }
            Event::UserEvent(UserEvent::Ipc(msg)) => {
                let m: Json = serde_json::from_str(&msg).unwrap_or(Json::Null);
                let t = m["t"].as_str().unwrap_or("");
                let name = m["name"].as_str().unwrap_or("").to_string();
                let mut push = true;
                match t {
                    "ready" => {}
                    "drag" => {
                        let _ = window.drag_window();
                        push = false;
                    }
                    "min" => {
                        window.set_minimized(true);
                        push = false;
                    }
                    "max" => {
                        window.set_maximized(!window.is_maximized());
                        push = false;
                    }
                    "close" => {
                        app.save_state();
                        *control_flow = ControlFlow::Exit;
                        push = false;
                    }
                    "show" => {
                        app.visible.insert(name.clone());
                        app.selected = Some(name);
                    }
                    "hide" => {
                        app.visible.remove(&name);
                    }
                    "toggle" => {
                        if !app.visible.remove(&name) {
                            app.visible.insert(name.clone());
                            app.selected = Some(name);
                        }
                    }
                    "showAll" => app.visible = app.uis.iter().map(|u| u.entry.name.clone()).collect(),
                    "hideAll" => app.visible.clear(),
                    "select" => app.selected = Some(name),
                    "device" => {
                        app.device = project::device(m["id"].as_str().unwrap_or("desktop"));
                        app.rescan_and_render_all();
                    }
                    "live" => {
                        app.live = m["on"].as_bool().unwrap_or(true);
                        if app.live && app.queued_changes {
                            app.queued_changes = false;
                            app.rescan_and_render_all();
                        }
                    }
                    "reload" => app.rescan_and_render_all(),
                    "reset" => {
                        if let Some(i) = app.idx(&name) {
                            app.render_ui(i);
                        }
                    }
                    "events" => {
                        let calls = m["calls"].as_array().cloned().unwrap_or_default();
                        if let Err(e) = app.fire(&name, &calls) {
                            app.logs.push(json!({"ui": name, "kind": "error", "text": e}));
                        }
                    }
                    "new" => {
                        let kind = m["kind"].as_str().unwrap_or("component");
                        match app.create_ui(&name, kind, None) {
                            Ok(path) => {
                                app.rescan_and_render_all();
                                app.visible.insert(name.clone());
                                app.selected = Some(name);
                                open_in_editor(&path);
                            }
                            Err(e) => {
                                let _ = webview.evaluate_script(&format!(
                                    "window.__luauui && window.__luauui.toast({})",
                                    Json::String(e)
                                ));
                            }
                        }
                    }
                    "edit" => {
                        if let Some(i) = app.idx(&name) {
                            open_in_editor(&app.uis[i].entry.path);
                        }
                        push = false;
                    }
                    "folder" => {
                        let _ = open::that_detached(&app.project.root);
                        push = false;
                    }
                    "openProject" => {
                        if let Some(dir) = rfd::FileDialog::new().set_directory(&app.project.root).pick_folder() {
                            if let Err(e) = app.set_project(&dir) {
                                app.logs.push(json!({"ui": "", "kind": "error", "text": e}));
                            }
                            *root_for_assets.lock().unwrap() = app.project.root.clone();
                        }
                    }
                    "clearLogs" => app.logs.clear(),
                    "reply" => {
                        push = false;
                        let id = m["id"].as_u64().unwrap_or(0);
                        match app.pending.remove(&id) {
                            Some(Pending::Layout(r)) => {
                                let _ = r.send(ok(m["data"].clone()));
                            }
                            Some(Pending::Screenshot(r)) => {
                                let d = &m["data"];
                                let rect = (
                                    d["x"].as_f64().unwrap_or(0.0).round() as i32,
                                    d["y"].as_f64().unwrap_or(0.0).round() as i32,
                                    d["w"].as_f64().unwrap_or(1.0).round() as i32,
                                    d["h"].as_f64().unwrap_or(1.0).round() as i32,
                                );
                                use base64::Engine;
                                let res = match capture(&window, rect) {
                                    Ok(png) => ok(json!({
                                        "png_base64": base64::engine::general_purpose::STANDARD.encode(png),
                                        "width": rect.2, "height": rect.3,
                                    })),
                                    Err(e) => err(500, e),
                                };
                                let _ = r.send(res);
                            }
                            None => {}
                        }
                    }
                    _ => push = false,
                }
                if push {
                    app.save_state();
                    app.push(&webview);
                }
            }
            _ => {}
        }
    });
}
