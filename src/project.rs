//! Project layout, UI discovery, templates, devices and a text outline of trees.

use crate::runtime::slash;
use serde::{Deserialize, Serialize};
use serde_json::Value as Json;
use std::path::{Path, PathBuf};

pub const API_PORT: u16 = 47821;

#[derive(Debug, Clone, Serialize)]
pub struct UiEntry {
    /// Name relative to the UI folder, without extension (`Shop`, `menus/Settings`).
    pub name: String,
    pub path: PathBuf,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ProjectConfig {
    #[serde(rename = "uiDir", default)]
    pub ui_dir: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Project {
    pub root: PathBuf,
    pub ui_dir: PathBuf,
}

impl Project {
    pub fn open(root: &Path) -> Self {
        let root = std::fs::canonicalize(root)
            .map(|p| PathBuf::from(p.to_string_lossy().trim_start_matches(r"\\?\").to_string()))
            .unwrap_or_else(|_| root.to_path_buf());
        let cfg: ProjectConfig = std::fs::read_to_string(root.join("luauui.json"))
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        let ui_dir = match cfg.ui_dir {
            Some(d) => root.join(d),
            None => {
                if root.join("ui").is_dir() {
                    root.join("ui")
                } else if root.join("src").join("ui").is_dir() {
                    root.join("src").join("ui")
                } else {
                    root.join("ui")
                }
            }
        };
        Self { root, ui_dir }
    }

    pub fn name(&self) -> String {
        self.root
            .file_name()
            .map(|s| s.to_string_lossy().to_string())
            .unwrap_or_else(|| slash(&self.root))
    }

    /// Every `.luau`/`.lua` file under the UI folder; files or folders starting
    /// with `_` are shared modules and are not listed.
    pub fn find_uis(&self) -> Vec<UiEntry> {
        let mut out = Vec::new();
        walk(&self.ui_dir, &self.ui_dir, &mut out);
        out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        out
    }

    pub fn ui_path(&self, name: &str) -> Option<PathBuf> {
        if !valid_name(name) {
            return None;
        }
        let p = self.ui_dir.join(format!("{name}.luau"));
        Some(p)
    }

    pub fn state_file(&self) -> PathBuf {
        self.root.join(".luauui").join("state.json")
    }
}

pub fn valid_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() < 120
        && !name.contains("..")
        && !name.starts_with('/')
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-' || c == '/')
}

fn walk(base: &Path, dir: &Path, out: &mut Vec<UiEntry>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        let fname = e.file_name().to_string_lossy().to_string();
        if fname.starts_with('_') || fname.starts_with('.') {
            continue;
        }
        if p.is_dir() {
            walk(base, &p, out);
        } else if let Some(ext) = p.extension().and_then(|x| x.to_str()) {
            if ext == "luau" || ext == "lua" {
                let rel = p.strip_prefix(base).unwrap_or(&p);
                let mut name = slash(rel);
                name = name.trim_end_matches(".luau").trim_end_matches(".lua").to_string();
                if name.ends_with("/init") {
                    name = name.trim_end_matches("/init").to_string();
                }
                out.push(UiEntry { name, path: p });
            }
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize)]
pub struct Device {
    pub id: &'static str,
    pub label: &'static str,
    pub w: f64,
    pub h: f64,
}

pub const DEVICES: &[Device] = &[
    Device { id: "desktop", label: "Desktop 1920×1080", w: 1920.0, h: 1080.0 },
    Device { id: "laptop", label: "Laptop 1366×768", w: 1366.0, h: 768.0 },
    Device { id: "tablet", label: "Tablet 1024×768", w: 1024.0, h: 768.0 },
    Device { id: "phone", label: "Phone 844×390", w: 844.0, h: 390.0 },
    Device { id: "phone-portrait", label: "Phone portrait 390×844", w: 390.0, h: 844.0 },
    Device { id: "console", label: "Console 1920×1080", w: 1920.0, h: 1080.0 },
];

pub fn device(id: &str) -> Device {
    *DEVICES.iter().find(|d| d.id == id).unwrap_or(&DEVICES[0])
}

pub fn template_component(name: &str) -> String {
    let short = name.rsplit('/').next().unwrap_or(name);
    format!(
        r#"local LuauUI = require(Packages.LuauUI)
local e = LuauUI.createElement

local function {short}(props)
	local count, setCount = LuauUI.useState(0)

	return e("ScreenGui", {{ IgnoreGuiInset = true }}, {{
		Panel = e("Frame", {{
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(380, 220),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
		}}, {{
			Corner = e("UICorner", {{ CornerRadius = UDim.new(0, 20) }}),
			Gradient = e("UIGradient", {{
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(58, 58, 58), Color3.fromRGB(8, 8, 8)),
			}}),
			Title = e("TextLabel", {{
				Text = "{short}",
				Size = UDim2.new(1, 0, 0, 60),
				BackgroundTransparency = 1,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				FontFace = Font.fromName("Montserrat", Enum.FontWeight.Bold),
				TextSize = 28,
			}}),
			Button = e("TextButton", {{
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -24),
				Size = UDim2.fromOffset(220, 52),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
				Text = "Clicks: " .. count,
				TextColor3 = Color3.fromRGB(10, 10, 10),
				FontFace = Font.fromName("Montserrat", Enum.FontWeight.Bold),
				TextSize = 20,
				[LuauUI.Event.Activated] = function()
					setCount(count + 1)
				end,
			}}, {{
				Corner = e("UICorner", {{ CornerRadius = UDim.new(1, 0) }}),
			}}),
		}}),
	}})
end

return {short}
"#
    )
}

pub fn template_instance(name: &str) -> String {
    let short = name.rsplit('/').next().unwrap_or(name);
    format!(
        r#"local gui = Instance.new("ScreenGui")
gui.Name = "{short}"
gui.IgnoreGuiInset = true

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(380, 220)
panel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 20)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Text = "{short}"
title.Size = UDim2.new(1, 0, 0, 60)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.FontFace = Font.fromName("Montserrat", Enum.FontWeight.Bold)
title.TextSize = 28
title.Parent = panel

local button = Instance.new("TextButton")
button.AnchorPoint = Vector2.new(0.5, 1)
button.Position = UDim2.new(0.5, 0, 1, -24)
button.Size = UDim2.fromOffset(220, 52)
button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
button.BorderSizePixel = 0
button.Text = "Click me"
button.TextColor3 = Color3.fromRGB(10, 10, 10)
button.FontFace = Font.fromName("Montserrat", Enum.FontWeight.Bold)
button.TextSize = 20
button.Parent = panel

local clicks = 0
button.Activated:Connect(function()
	clicks += 1
	button.Text = "Clicks: " .. clicks
end)

return gui
"#
    )
}

/// Compact, readable outline of a rendered tree (for MCP and logs).
pub fn outline(roots: &Json) -> String {
    let mut s = String::new();
    for r in as_list(roots) {
        outline_node(r, 0, &mut s);
    }
    if s.is_empty() {
        s.push_str("(nothing rendered)\n");
    }
    s
}

pub fn as_list(v: &Json) -> Vec<&Json> {
    match v {
        Json::Array(a) => a.iter().collect(),
        Json::Object(o) => o.values().collect(),
        _ => vec![],
    }
}

fn fmt_val(v: &Json) -> String {
    match v {
        Json::Object(o) => match o.get("t").and_then(|t| t.as_str()) {
            Some("UDim2") => format!(
                "{{{},{}}},{{{},{}}}",
                num(&o["xs"]), num(&o["xo"]), num(&o["ys"]), num(&o["yo"])
            ),
            Some("UDim") => format!("{{{},{}}}", num(&o["s"]), num(&o["o"])),
            Some("V2") => format!("({},{})", num(&o["x"]), num(&o["y"])),
            Some("C3") => {
                let c = |k: &str| (o[k].as_f64().unwrap_or(0.0).clamp(0.0, 1.0) * 255.0).round() as u8;
                format!("#{:02X}{:02X}{:02X}", c("r"), c("g"), c("b"))
            }
            Some("E") => format!("{}.{}", o["e"].as_str().unwrap_or(""), o["n"].as_str().unwrap_or("")),
            Some("Font") => format!(
                "{}/{}",
                o["f"].as_str().unwrap_or("").rsplit('/').next().unwrap_or("").trim_end_matches(".json"),
                o["w"].as_str().unwrap_or("")
            ),
            Some("CS") => {
                let n = o.get("k").map(|k| as_list(k).len()).unwrap_or(0);
                format!("ColorSequence[{n}]")
            }
            Some("NS") => "NumberSequence".into(),
            Some(t) => t.to_string(),
            None => "{}".into(),
        },
        Json::String(s) => {
            let mut t: String = s.chars().take(60).collect();
            if s.chars().count() > 60 {
                t.push('…');
            }
            format!("{t:?}")
        }
        other => other.to_string(),
    }
}

fn num(v: &Json) -> String {
    let f = v.as_f64().unwrap_or(0.0);
    if (f - f.round()).abs() < 1e-9 {
        format!("{}", f.round() as i64)
    } else {
        format!("{:.3}", f).trim_end_matches('0').to_string()
    }
}

const KEY_PROPS: &[&str] = &[
    "Text", "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency",
    "TextColor3", "TextSize", "TextScaled", "FontFace", "Font", "Image", "Visible", "LayoutOrder",
    "ZIndex", "AutomaticSize", "CornerRadius", "Color", "Thickness", "Rotation", "Padding",
    "FillDirection", "HorizontalAlignment", "VerticalAlignment", "CellSize", "AspectRatio",
    "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight", "IgnoreGuiInset", "Enabled",
    "DisplayOrder", "PlaceholderText", "ClipsDescendants", "CanvasSize", "Scale",
];

fn outline_node(n: &Json, depth: usize, s: &mut String) {
    let cls = n["c"].as_str().unwrap_or("?");
    let name = n["n"].as_str().unwrap_or("");
    s.push_str(&"  ".repeat(depth));
    s.push_str(cls);
    if name != cls {
        s.push_str(&format!(" \"{name}\""));
    }
    if let Some(p) = n["p"].as_object() {
        for k in KEY_PROPS {
            if let Some(v) = p.get(*k) {
                s.push_str(&format!(" {k}={}", fmt_val(v)));
            }
        }
    }
    if let Some(ev) = n["ev"].as_object() {
        if !ev.is_empty() {
            let names: Vec<&str> = ev.keys().map(|k| k.as_str()).collect();
            s.push_str(&format!(" [events: {}]", names.join(", ")));
        }
    }
    s.push('\n');
    if let Some(k) = n.get("k") {
        for c in as_list(k) {
            outline_node(c, depth + 1, s);
        }
    }
}

/// Finds a node by slash path of names (`Shop/Panel/Buy`); the first segment
/// may be the root's name or skipped.
pub fn find_node<'a>(roots: &'a Json, path: &str) -> Option<&'a Json> {
    let segs: Vec<&str> = path.split(['/', '.']).filter(|s| !s.is_empty()).collect();
    if segs.is_empty() {
        return None;
    }
    fn go<'a>(nodes: Vec<&'a Json>, segs: &[&str]) -> Option<&'a Json> {
        for n in nodes {
            if n["n"].as_str() == Some(segs[0]) {
                if segs.len() == 1 {
                    return Some(n);
                }
                if let Some(f) = go(as_list(&n["k"]), &segs[1..]) {
                    return Some(f);
                }
            }
        }
        None
    }
    if let Some(f) = go(as_list(roots), &segs) {
        return Some(f);
    }
    // fallback: search anywhere for the full path starting at any depth
    fn any<'a>(nodes: Vec<&'a Json>, segs: &[&str]) -> Option<&'a Json> {
        for n in nodes {
            if let Some(f) = go(vec![n], segs) {
                return Some(f);
            }
            if let Some(f) = any(as_list(&n["k"]), segs) {
                return Some(f);
            }
        }
        None
    }
    any(as_list(roots), &segs)
}
