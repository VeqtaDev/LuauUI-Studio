--!nocheck
-- LuauUI preview runtime.
-- Emulates the parts of the Roblox client API that UI code uses, plus a small
-- React/Roact-compatible library (LuauUI), and serializes the result to plain
-- tables the viewer can draw.

local HOST = __HOST
__HOST = nil

local rawtypeof = typeof
local unpack = table.unpack or unpack

----------------------------------------------------------------------
-- Logging
----------------------------------------------------------------------
local function fmtArgs(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

print = function(...)
	HOST.log("print", fmtArgs(...))
end
warn = function(...)
	HOST.log("warn", fmtArgs(...))
end

----------------------------------------------------------------------
-- Datatypes
----------------------------------------------------------------------
local function tag(v)
	return type(v) == "table" and rawget(v, "__t") or nil
end

-- UDim
UDim = {}
local UDimMT = { __index = UDim }
function UDim.new(s, o)
	return setmetatable({ __t = "UDim", Scale = s or 0, Offset = o or 0 }, UDimMT)
end
UDimMT.__add = function(a, b) return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset) end
UDimMT.__sub = function(a, b) return UDim.new(a.Scale - b.Scale, a.Offset - b.Offset) end
UDimMT.__unm = function(a) return UDim.new(-a.Scale, -a.Offset) end
UDimMT.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
UDimMT.__tostring = function(a) return string.format("%g, %g", a.Scale, a.Offset) end

-- UDim2
UDim2 = {}
local UDim2MT = {}
UDim2MT.__index = function(t, k)
	if k == "Width" then return rawget(t, "X") end
	if k == "Height" then return rawget(t, "Y") end
	return UDim2[k]
end
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then
		return setmetatable({ __t = "UDim2", X = xs, Y = xo or UDim.new() }, UDim2MT)
	end
	return setmetatable({ __t = "UDim2", X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UDim2MT)
end
function UDim2.fromScale(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end
function UDim2.fromOffset(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
function UDim2:Lerp(g, a)
	return UDim2.new(
		self.X.Scale + (g.X.Scale - self.X.Scale) * a, self.X.Offset + (g.X.Offset - self.X.Offset) * a,
		self.Y.Scale + (g.Y.Scale - self.Y.Scale) * a, self.Y.Offset + (g.Y.Offset - self.Y.Offset) * a)
end
UDim2MT.__add = function(a, b) return UDim2.new(a.X + b.X, a.Y + b.Y) end
UDim2MT.__sub = function(a, b) return UDim2.new(a.X - b.X, a.Y - b.Y) end
UDim2MT.__unm = function(a) return UDim2.new(-a.X, -a.Y) end
UDim2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
UDim2MT.__tostring = function(a) return string.format("{%s}, {%s}", tostring(a.X), tostring(a.Y)) end

-- Vector2 / Vector3
Vector2 = {}
local V2MT = {}
V2MT.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
	if k == "Unit" then
		local m = math.sqrt(t.X * t.X + t.Y * t.Y)
		return m == 0 and Vector2.new() or Vector2.new(t.X / m, t.Y / m)
	end
	return Vector2[k]
end
function Vector2.new(x, y) return setmetatable({ __t = "Vector2", X = x or 0, Y = y or 0 }, V2MT) end
local function v2op(f)
	return function(a, b)
		if type(a) == "number" then a = Vector2.new(a, a) end
		if type(b) == "number" then b = Vector2.new(b, b) end
		return Vector2.new(f(a.X, b.X), f(a.Y, b.Y))
	end
end
V2MT.__add = v2op(function(a, b) return a + b end)
V2MT.__sub = v2op(function(a, b) return a - b end)
V2MT.__mul = v2op(function(a, b) return a * b end)
V2MT.__div = v2op(function(a, b) return a / b end)
V2MT.__unm = function(a) return Vector2.new(-a.X, -a.Y) end
V2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2MT.__tostring = function(a) return string.format("%g, %g", a.X, a.Y) end
function Vector2:Lerp(g, a) return Vector2.new(self.X + (g.X - self.X) * a, self.Y + (g.Y - self.Y) * a) end
function Vector2:Dot(o) return self.X * o.X + self.Y * o.Y end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)
Vector2.xAxis = Vector2.new(1, 0)
Vector2.yAxis = Vector2.new(0, 1)

Vector3 = {}
local V3MT = { __index = Vector3 }
function Vector3.new(x, y, z) return setmetatable({ __t = "Vector3", X = x or 0, Y = y or 0, Z = z or 0 }, V3MT) end
V3MT.__tostring = function(a) return string.format("%g, %g, %g", a.X, a.Y, a.Z) end
Vector3.zero = Vector3.new()
Vector3.one = Vector3.new(1, 1, 1)

-- Color3
Color3 = {}
local C3MT = { __index = Color3 }
local function clamp01(x) return math.clamp(x or 0, 0, 1) end
function Color3.new(r, g, b) return setmetatable({ __t = "Color3", R = r or 0, G = g or 0, B = b or 0 }, C3MT) end
function Color3.fromRGB(r, g, b) return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
function Color3.fromHex(hex)
	hex = string.gsub(hex, "#", "")
	if #hex == 3 then
		hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
	end
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16) or 0, tonumber(hex:sub(3, 4), 16) or 0, tonumber(hex:sub(5, 6), 16) or 0)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return Color3.new(v, t, p) end
	if i == 1 then return Color3.new(q, v, p) end
	if i == 2 then return Color3.new(p, v, t) end
	if i == 3 then return Color3.new(p, q, v) end
	if i == 4 then return Color3.new(t, p, v) end
	return Color3.new(v, p, q)
end
function Color3.toHSV(c) return c:ToHSV() end
function Color3:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d ~= 0 then
		if mx == r then h = ((g - b) / d) % 6
		elseif mx == g then h = (b - r) / d + 2
		else h = (r - g) / d + 4 end
		h = h / 6
	end
	return h, mx == 0 and 0 or d / mx, mx
end
function Color3:Lerp(g, a)
	return Color3.new(self.R + (g.R - self.R) * a, self.G + (g.G - self.G) * a, self.B + (g.B - self.B) * a)
end
function Color3:ToHex()
	return string.format("%02X%02X%02X", clamp01(self.R) * 255 + 0.5, clamp01(self.G) * 255 + 0.5, clamp01(self.B) * 255 + 0.5)
end
C3MT.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3MT.__tostring = function(a) return string.format("%g, %g, %g", a.R, a.G, a.B) end

-- Sequences
ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, c) return { __t = "ColorSequenceKeypoint", Time = t, Value = c } end
ColorSequence = {}
function ColorSequence.new(a, b)
	local kps
	if tag(a) == "Color3" then
		kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	else
		kps = a or {}
	end
	return { __t = "ColorSequence", Keypoints = kps }
end
NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, v, e) return { __t = "NumberSequenceKeypoint", Time = t, Value = v, Envelope = e or 0 } end
NumberSequence = {}
function NumberSequence.new(a, b)
	local kps
	if type(a) == "number" then
		kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
	else
		kps = a or {}
	end
	return { __t = "NumberSequence", Keypoints = kps }
end
NumberRange = {}
function NumberRange.new(a, b) return { __t = "NumberRange", Min = a or 0, Max = b or a or 0 } end
Rect = {}
function Rect.new(a, b, c, d)
	if tag(a) == "Vector2" then
		return { __t = "Rect", Min = a, Max = b, Width = b.X - a.X, Height = b.Y - a.Y }
	end
	a, b, c, d = a or 0, b or 0, c or 0, d or 0
	return { __t = "Rect", Min = Vector2.new(a, b), Max = Vector2.new(c, d), Width = c - a, Height = d - b }
end
TweenInfo = {}
function TweenInfo.new(t, style, dir, rep, rev, delay)
	return { __t = "TweenInfo", Time = t or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = rep or 0, Reverses = rev or false, DelayTime = delay or 0 }
end
DateTime = {}
function DateTime.now() return { UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 } end
Random = {}
function Random.new()
	local r = {}
	function r:NextInteger(a, b) return math.random(a, b) end
	function r:NextNumber(a, b) a = a or 0; b = b or 1; return a + math.random() * (b - a) end
	return r
end

-- Enum
local enumTypes = {}
Enum = setmetatable({}, {
	__index = function(_, typ)
		local t = enumTypes[typ]
		if not t then
			local items = {}
			t = setmetatable({}, {
				__index = function(tt, name)
					if name == "GetEnumItems" then
						return function() local out = {} for _, v in pairs(items) do table.insert(out, v) end return out end
					end
					local item = setmetatable({ __t = "EnumItem", EnumType = typ, Name = name, Value = 0 }, {
						__tostring = function() return "Enum." .. typ .. "." .. name end,
					})
					items[name] = item
					rawset(tt, name, item)
					return item
				end,
				__tostring = function() return typ end,
			})
			enumTypes[typ] = t
		end
		return t
	end,
})

-- Font
Font = {}
local FontMT = { __index = Font }
function Font.new(family, weight, style)
	return setmetatable({ __t = "Font", Family = family or "rbxasset://fonts/families/SourceSansPro.json", Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, FontMT)
end
function Font.fromName(name, weight, style)
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
function Font.fromEnum(e)
	return setmetatable({ __t = "Font", FromEnum = e.Name, Family = e.Name, Weight = Enum.FontWeight.Regular, Style = Enum.FontStyle.Normal }, FontMT)
end
function Font.fromId(id, weight, style)
	return Font.new("rbxassetid://" .. tostring(id), weight, style)
end

----------------------------------------------------------------------
-- Signals
----------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ _h = {} }, Signal) end
function Signal:Connect(fn)
	local entry = { fn = fn }
	table.insert(self._h, entry)
	local conn = { Connected = true }
	function conn.Disconnect()
		conn.Connected = false
		local i = table.find(self._h, entry)
		if i then table.remove(self._h, i) end
	end
	return conn
end
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn.Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Wait()
	if coroutine.isyieldable() then coroutine.yield() end
end
local function safeCall(fn, ...)
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		HOST.log("error", debug.traceback(co, tostring(err)))
	end
end
function Signal:Fire(...)
	for _, entry in ipairs(table.clone(self._h)) do
		safeCall(entry.fn, ...)
	end
end
function Signal:HasListeners() return #self._h > 0 end

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------
local INST = setmetatable({}, { __mode = "k" })
local InstanceMT = {}
local Methods = {}

local EVENT_NAMES = {
	Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
	MouseButton2Click = true, MouseEnter = true, MouseLeave = true, MouseMoved = true,
	FocusLost = true, Focused = true, Changed = true, InputBegan = true, InputEnded = true,
	InputChanged = true, ChildAdded = true, ChildRemoved = true, Destroying = true,
	AncestryChanged = true, DescendantAdded = true, MouseWheelForward = true, MouseWheelBackward = true,
	ReturnPressedFromOnScreenKeyboard = true, SelectionGained = true, SelectionLost = true,
	Heartbeat = true, RenderStepped = true, Stepped = true, PlayerAdded = true, PlayerRemoving = true,
	TouchTap = true, Completed = true, ValueChanged = true,
}

local GUI_OBJECTS = {
	Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true,
	ImageButton = true, ScrollingFrame = true, CanvasGroup = true, ViewportFrame = true, VideoFrame = true,
}
local GUI_BUTTONS = { TextButton = true, ImageButton = true }
local LAYER_COLLECTORS = { ScreenGui = true, BillboardGui = true, SurfaceGui = true }

local READ_DEFAULTS = {
	Size = UDim2.new(), Position = UDim2.new(), AnchorPoint = Vector2.new(), Visible = true,
	BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(163, 162, 165), Rotation = 0,
	ZIndex = 1, LayoutOrder = 0, TextTransparency = 0, ImageTransparency = 0, TextSize = 14,
	TextColor3 = Color3.fromRGB(27, 42, 53), Enabled = true, Transparency = 0, Thickness = 1,
	AbsoluteSize = Vector2.new(), AbsolutePosition = Vector2.new(), AbsoluteRotation = 0,
	Text = "", Image = "", Value = nil, DisplayOrder = 0, Scale = 1, GroupTransparency = 0,
	CanvasPosition = Vector2.new(), CanvasSize = UDim2.new(0, 0, 2, 0),
}

local function isInstance(v)
	return type(v) == "table" and INST[v] ~= nil
end

local function newInstance(className)
	local self = setmetatable({}, InstanceMT)
	INST[self] = {
		ClassName = className,
		Name = className,
		Parent = nil,
		children = {},
		props = {},
		signals = {},
		propSignals = {},
		attrs = {},
	}
	return self
end

local function getSignal(d, name)
	local s = d.signals[name]
	if not s then
		s = Signal.new()
		d.signals[name] = s
	end
	return s
end

local function setParent(self, parent)
	local d = INST[self]
	if d.Parent == parent then return end
	if d.Parent then
		local pd = INST[d.Parent]
		local i = table.find(pd.children, self)
		if i then table.remove(pd.children, i) end
		if pd.signals.ChildRemoved then pd.signals.ChildRemoved:Fire(self) end
	end
	d.Parent = parent
	if parent then
		local pd = INST[parent]
		if not pd then error("Parent must be an Instance", 3) end
		table.insert(pd.children, self)
		if pd.signals.ChildAdded then pd.signals.ChildAdded:Fire(self) end
	end
end

InstanceMT.__index = function(self, k)
	local d = INST[self]
	if k == "ClassName" then return d.ClassName end
	if k == "Name" then return d.Name end
	if k == "Parent" then return d.Parent end
	local m = Methods[k]
	if m then return m end
	local v = d.props[k]
	if v ~= nil then return v end
	if EVENT_NAMES[k] then return getSignal(d, k) end
	for _, c in ipairs(d.children) do
		if INST[c].Name == k then return c end
	end
	return READ_DEFAULTS[k]
end
InstanceMT.__newindex = function(self, k, v)
	local d = INST[self]
	if k == "Parent" then
		setParent(self, v)
	elseif k == "Name" then
		d.Name = tostring(v)
	elseif k == "ClassName" then
		error("ClassName is read-only", 2)
	else
		local old = d.props[k]
		d.props[k] = v
		if old ~= v then
			if d.propSignals[k] then d.propSignals[k]:Fire() end
			if d.signals.Changed then d.signals.Changed:Fire(k) end
		end
	end
end
InstanceMT.__tostring = function(self) return INST[self].Name end

function Methods:GetChildren() return table.clone(INST[self].children) end
function Methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in ipairs(INST[i].children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Methods:FindFirstChild(name, recursive)
	for _, c in ipairs(INST[self].children) do
		if INST[c].Name == name then return c end
	end
	if recursive then
		for _, c in ipairs(INST[self].children) do
			local f = c:FindFirstChild(name, true)
			if f then return f end
		end
	end
	return nil
end
function Methods:WaitForChild(name)
	local c = self:FindFirstChild(name)
	if not c then HOST.log("warn", "WaitForChild('" .. tostring(name) .. "') : not found in " .. INST[self].Name) end
	return c
end
function Methods:FindFirstChildOfClass(cls)
	for _, c in ipairs(INST[self].children) do
		if INST[c].ClassName == cls then return c end
	end
end
function Methods:FindFirstChildWhichIsA(cls, recursive)
	for _, c in ipairs(INST[self].children) do
		if c:IsA(cls) then return c end
	end
	if recursive then
		for _, c in ipairs(INST[self].children) do
			local f = c:FindFirstChildWhichIsA(cls, true)
			if f then return f end
		end
	end
end
function Methods:FindFirstAncestor(name)
	local p = INST[self].Parent
	while p do
		if INST[p].Name == name then return p end
		p = INST[p].Parent
	end
end
function Methods:FindFirstAncestorOfClass(cls)
	local p = INST[self].Parent
	while p do
		if INST[p].ClassName == cls then return p end
		p = INST[p].Parent
	end
end
Methods.FindFirstAncestorWhichIsA = function(self, cls)
	local p = INST[self].Parent
	while p do
		if p:IsA(cls) then return p end
		p = INST[p].Parent
	end
end
function Methods:IsA(cls)
	local c = INST[self].ClassName
	if c == cls or cls == "Instance" then return true end
	if cls == "GuiObject" then return GUI_OBJECTS[c] == true end
	if cls == "GuiButton" then return GUI_BUTTONS[c] == true end
	if cls == "LayerCollector" then return LAYER_COLLECTORS[c] == true end
	if cls == "GuiBase2d" or cls == "GuiBase" then return GUI_OBJECTS[c] == true or LAYER_COLLECTORS[c] == true end
	if cls == "UIComponent" then return c:sub(1, 2) == "UI" end
	if cls == "UIGridStyleLayout" then return c == "UIListLayout" or c == "UIGridLayout" or c == "UIPageLayout" or c == "UITableLayout" end
	if cls == "UIConstraint" then return c == "UIAspectRatioConstraint" or c == "UISizeConstraint" or c == "UITextSizeConstraint" end
	return false
end
function Methods:IsDescendantOf(other)
	local p = INST[self].Parent
	while p do
		if p == other then return true end
		p = INST[p].Parent
	end
	return false
end
function Methods:IsAncestorOf(other) return other:IsDescendantOf(self) end
function Methods:Destroy()
	local d = INST[self]
	if d.signals.Destroying then d.signals.Destroying:Fire() end
	for _, c in ipairs(table.clone(d.children)) do c:Destroy() end
	setParent(self, nil)
end
function Methods:Remove() setParent(self, nil) end
function Methods:ClearAllChildren()
	for _, c in ipairs(table.clone(INST[self].children)) do c:Destroy() end
end
function Methods:Clone()
	local d = INST[self]
	local copy = newInstance(d.ClassName)
	local cd = INST[copy]
	cd.Name = d.Name
	for k, v in pairs(d.props) do cd.props[k] = v end
	for k, v in pairs(d.attrs) do cd.attrs[k] = v end
	for _, c in ipairs(d.children) do
		c:Clone().Parent = copy
	end
	return copy
end
function Methods:GetFullName()
	local parts = {}
	local i = self
	while i do
		table.insert(parts, 1, INST[i].Name)
		i = INST[i].Parent
	end
	return table.concat(parts, ".")
end
function Methods:GetPropertyChangedSignal(prop)
	local d = INST[self]
	local s = d.propSignals[prop]
	if not s then
		s = Signal.new()
		d.propSignals[prop] = s
	end
	return s
end
function Methods:SetAttribute(k, v) INST[self].attrs[k] = v end
function Methods:GetAttribute(k) return INST[self].attrs[k] end
function Methods:GetAttributes() return table.clone(INST[self].attrs) end
function Methods:GetAttributeChangedSignal() return Signal.new() end
function Methods:TweenSize(size, _, _, _, _, cb)
	self.Size = size
	if cb then safeCall(cb, Enum.TweenStatus.Completed) end
	return true
end
function Methods:TweenPosition(pos, _, _, _, _, cb)
	self.Position = pos
	if cb then safeCall(cb, Enum.TweenStatus.Completed) end
	return true
end
function Methods:TweenSizeAndPosition(size, pos, _, _, _, _, cb)
	self.Size = size
	self.Position = pos
	if cb then safeCall(cb, Enum.TweenStatus.Completed) end
	return true
end
function Methods:CaptureFocus() end
function Methods:ReleaseFocus() end
function Methods:IsFocused() return false end
function Methods:GetTags() return {} end
function Methods:HasTag() return false end
function Methods:AddTag() end
function Methods:RemoveTag() end

Instance = {}
-- lihfolk-ignore: instance-new-parent (this is the emulated constructor itself)
function Instance.new(className, parent)
	local inst = newInstance(className)
	if parent ~= nil then inst.Parent = parent end
	return inst
end
function Instance.fromExisting(i) return i:Clone() end

----------------------------------------------------------------------
-- task / legacy scheduling (preview runs one frame: waits stop the thread)
----------------------------------------------------------------------
local function yieldNow()
	if coroutine.isyieldable() then coroutine.yield() end
	return 0
end
task = {}
function task.wait(t) return yieldNow() end
function task.spawn(fn, ...)
	if type(fn) == "thread" then
		coroutine.resume(fn, ...)
		return fn
	end
	local co = coroutine.create(fn)
	local ok, err = coroutine.resume(co, ...)
	if not ok then HOST.log("error", debug.traceback(co, tostring(err))) end
	return co
end
task.defer = task.spawn
function task.delay() return nil end
function task.cancel() end
function task.synchronize() end
function task.desynchronize() end
wait = task.wait
spawn = function(fn) return task.spawn(fn) end
delay = function() end
local clock0 = os.clock()
tick = function() return os.time() + (os.clock() % 1) end
time = function() return os.clock() - clock0 end
elapsedTime = time
shared = {}

typeof = function(v)
	if isInstance(v) then return "Instance" end
	if type(v) == "table" then
		local t = rawget(v, "__t")
		if t then return t end
		if rawget(v, "__proxy") then return "Instance" end
	end
	return rawtypeof(v)
end

----------------------------------------------------------------------
-- Services / DataModel
----------------------------------------------------------------------
local deviceW, deviceH = HOST.device()

local player = newInstance("Player")
INST[player].Name = "Player"
player.UserId = 1
player.DisplayName = "Player"
-- lihfolk-ignore: instance-new-parent (preview container, nothing replicates)
local playerGui = Instance.new("PlayerGui", player)
INST[playerGui].Name = "PlayerGui"
local starterGui = newInstance("StarterGui")
INST[starterGui].Name = "StarterGui"
starterGui.SetCoreGuiEnabled = function() end
starterGui.GetCoreGuiEnabled = function() return true end
starterGui.SetCore = function() end
starterGui.GetCore = function() return nil end
player.GetMouse = function()
	return { X = 0, Y = 0, Hit = nil, Button1Down = Signal.new(), Button1Up = Signal.new(), Move = Signal.new() }
end
player.Kick = function() end

local function makeService(name, fields)
	local s = newInstance(name)
	INST[s].Name = name
	for k, v in pairs(fields or {}) do
		s[k] = v
	end
	return s
end

local currentCamera = makeService("Camera", { ViewportSize = Vector2.new(deviceW, deviceH) })
local services = {}
services.Players = makeService("Players", {
	LocalPlayer = player,
	GetPlayers = function() return { player } end,
	GetUserThumbnailAsync = function() return "rbxasset://textures/ui/GuiImagePlaceholder.png", true end,
	GetNameFromUserIdAsync = function() return "Player" end,
	GetPlayerFromCharacter = function() return nil end,
})
services.StarterGui = starterGui
services.Workspace = makeService("Workspace", { CurrentCamera = currentCamera })
services.TweenService = makeService("TweenService", {
	Create = function(_, inst, _info, goals)
		local tween = { Completed = Signal.new(), PlaybackState = Enum.PlaybackState.Begin }
		function tween:Play()
			if isInstance(inst) then
				for k, v in pairs(goals) do inst[k] = v end
			end
			tween.PlaybackState = Enum.PlaybackState.Completed
			tween.Completed:Fire(Enum.PlaybackState.Completed)
		end
		function tween:Cancel() end
		function tween:Pause() end
		function tween:Destroy() end
		return tween
	end,
	GetValue = function(_, a) return a end,
})
services.RunService = makeService("RunService", {
	IsStudio = function() return true end,
	IsClient = function() return true end,
	IsServer = function() return false end,
	IsRunning = function() return false end,
	BindToRenderStep = function() end,
	UnbindFromRenderStep = function() end,
})
services.UserInputService = makeService("UserInputService", {
	TouchEnabled = deviceW < 1000 or deviceH < 500,
	KeyboardEnabled = true,
	MouseEnabled = true,
	GamepadEnabled = false,
	GetLastInputType = function() return Enum.UserInputType.MouseButton1 end,
	IsKeyDown = function() return false end,
	GetMouseLocation = function() return Vector2.new() end,
})
services.GuiService = makeService("GuiService", {
	GetGuiInset = function() return Vector2.new(0, 58), Vector2.new() end,
	IsTenFootInterface = function() return false end,
	TopbarInset = Rect.new(0, 0, deviceW, 58),
})
services.HttpService = makeService("HttpService", {
	JSONEncode = function(_, v) return HOST.json_encode(v) end,
	JSONDecode = function(_, s) return HOST.json_decode(s) end,
	GenerateGUID = function(_, braces)
		local g = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
			local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
			return string.format("%X", v)
		end)
		return braces == false and g or "{" .. g .. "}"
	end,
})
-- lihfolk-ignore: paid-random-no-policy (offline stub of the service, no purchase or random roll happens)
services.MarketplaceService = makeService("MarketplaceService", {
	UserOwnsGamePassAsync = function() return false end,
	PlayerOwnsAsset = function() return false end,
	PromptGamePassPurchase = function() HOST.log("print", "[MarketplaceService] PromptGamePassPurchase (preview)") end,
	PromptProductPurchase = function() HOST.log("print", "[MarketplaceService] PromptProductPurchase (preview)") end,
	PromptPurchase = function() end,
	GetProductInfo = function() return { Name = "Produit", PriceInRobux = 0 } end,
})
services.TextService = makeService("TextService", {
	GetTextSize = function(_, text, size, _font, frame)
		local w = #tostring(text) * size * 0.5
		return Vector2.new(frame and math.min(w, frame.X) or w, size)
	end,
})
services.SoundService = makeService("SoundService", { PlayLocalSound = function() end })
services.ContextActionService = makeService("ContextActionService", {
	BindAction = function() end, UnbindAction = function() end, BindActionAtPriority = function() end,
})
services.Lighting = makeService("Lighting")
services.Debris = makeService("Debris", { AddItem = function() end })
services.LocalizationService = makeService("LocalizationService", { RobloxLocaleId = "fr-fr", SystemLocaleId = "fr-fr" })
services.CollectionService = makeService("CollectionService", {
	GetTagged = function() return {} end,
	GetInstanceAddedSignal = function() return Signal.new() end,
	GetInstanceRemovedSignal = function() return Signal.new() end,
	HasTag = function() return false end,
})
services.SocialService = makeService("SocialService")
services.HapticService = makeService("HapticService")
services.VRService = makeService("VRService", { VREnabled = false })

----------------------------------------------------------------------
-- Path proxies (script, script.Parent, game.ReplicatedStorage...) for require
----------------------------------------------------------------------
local ROOT = HOST.root
local PathMT = {}
local function pathProxy(bases, name)
	return setmetatable({ __proxy = true, __bases = bases, __name = name }, PathMT)
end
local function parentDir(p)
	local d = string.match(p, "^(.*)/[^/]+$")
	return d or p
end
PathMT.__index = function(self, k)
	if k == "Parent" then
		local nb = {}
		for i, b in ipairs(rawget(self, "__bases")) do nb[i] = parentDir(b) end
		return pathProxy(nb, string.match(nb[1], "([^/]+)$") or "")
	end
	if k == "Name" then return rawget(self, "__name") end
	if k == "ClassName" then return "Folder" end
	if k == "WaitForChild" or k == "FindFirstChild" then
		return function(this, child) return this[child] end
	end
	if k == "IsA" then return function() return false end end
	if k == "GetChildren" then return function() return {} end end
	local nb = {}
	for i, b in ipairs(rawget(self, "__bases")) do nb[i] = b .. "/" .. k end
	return pathProxy(nb, k)
end
PathMT.__tostring = function(self) return rawget(self, "__name") end

local SOURCE_SERVICES = {
	ReplicatedStorage = true, ReplicatedFirst = true, StarterPlayer = true, ServerStorage = true,
	ServerScriptService = true, StarterPlayerScripts = true,
}
local function serviceProxy(name)
	return pathProxy({
		ROOT .. "/" .. name,
		ROOT .. "/src/" .. name,
		ROOT,
		ROOT .. "/src",
		ROOT .. "/src/shared",
		ROOT .. "/ui",
	}, name)
end

local game = makeService("DataModel")
INST[game].Name = "Game"
local function getService(_, name)
	if services[name] then return services[name] end
	if SOURCE_SERVICES[name] then
		services[name] = serviceProxy(name)
		return services[name]
	end
	services[name] = makeService(name)
	return services[name]
end
game.GetService = getService
game.FindService = getService
game.PlaceId = 0
game.GameId = 0
game.JobId = "preview"
game.IsLoaded = function() return true end
game.BindToClose = function() end
game.Loaded = Signal.new()
-- game.Players, game.ReplicatedStorage, ... resolve as services
local dataModel = game
local proxiedGame = setmetatable({ __proxyGame = true }, {
	__index = function(_, k)
		if k == "GetService" or k == "FindService" then
			return function(_, name) return getService(nil, name) end
		end
		if services[k] or SOURCE_SERVICES[k] or (type(k) == "string" and k:match("Service$")) or k == "Players" or k == "Workspace" or k == "Lighting" or k == "StarterGui" then
			return getService(nil, k)
		end
		return dataModel[k]
	end,
	__newindex = function(_, k, v) dataModel[k] = v end,
	__tostring = function() return "Game" end,
})
_G.game = proxiedGame
game = proxiedGame
workspace = services.Workspace
Workspace = workspace

----------------------------------------------------------------------
-- LuauUI: React/Roact-compatible element library
----------------------------------------------------------------------
local LuauUI = { __lib = true }
LuauUI.None = setmetatable({}, { __tostring = function() return "LuauUI.None" end })
LuauUI.Fragment = { __fragment = true }
LuauUI.Children = { __childrenKey = true }
LuauUI.Ref = { __refKey = true }
LuauUI.Event = setmetatable({}, {
	__index = function(t, k)
		local key = { __eventKey = k }
		rawset(t, k, key)
		return key
	end,
})
LuauUI.Change = setmetatable({}, {
	__index = function(t, k)
		local key = { __changeKey = k }
		rawset(t, k, key)
		return key
	end,
})
LuauUI.Tag = "LuauUITag"

local function isElement(v)
	return type(v) == "table" and rawget(v, "__t") == "Element"
end

function LuauUI.createElement(component, props, ...)
	local n = select("#", ...)
	local children
	if n == 1 then
		children = ...
		if isElement(children) then children = { children } end
	elseif n > 1 then
		children = { ... }
	end
	return { __t = "Element", component = component, props = props or {}, children = children }
end
LuauUI.h = LuauUI.createElement

function LuauUI.createFragment(children)
	return LuauUI.createElement(LuauUI.Fragment, nil, children)
end

function LuauUI.createRef() return { current = nil, __ref = true } end
function LuauUI.forwardRef(render)
	return function(props) return render(props, props.ref) end
end
function LuauUI.memo(c) return c end

-- Bindings
local dirty = false
local function markDirty() dirty = true end

local BindingMT = {}
BindingMT.__index = BindingMT
function BindingMT:getValue()
	return self._get()
end
function BindingMT:map(fn)
	local src = self
	return setmetatable({ __binding = true, _get = function() return fn(src:getValue()) end }, BindingMT)
end
function LuauUI.createBinding(initial)
	local slot = { v = initial }
	local b = setmetatable({ __binding = true, _get = function() return slot.v end }, BindingMT)
	return b, function(v)
		if slot.v ~= v then
			slot.v = v
			markDirty()
		end
	end
end
function LuauUI.joinBindings(list)
	return setmetatable({ __binding = true, _get = function()
		local out = {}
		for k, b in pairs(list) do out[k] = b:getValue() end
		return out
	end }, BindingMT)
end
local function isBinding(v) return type(v) == "table" and rawget(v, "__binding") == true end

-- Context
function LuauUI.createContext(default)
	local ctx = { __context = true, default = default }
	ctx.Provider = { __provider = ctx }
	ctx.Consumer = { __consumer = ctx }
	return ctx
end
local contextStack = {}
local function readContext(ctx)
	for i = #contextStack, 1, -1 do
		if contextStack[i].ctx == ctx then return contextStack[i].value end
	end
	return ctx.default
end

-- Hooks
local hookStore = {}
local currentHooks = nil
local pendingEffects = {}

local function nextSlot()
	local h = currentHooks
	if not h then error("Hooks (useState, ...) must be called inside a component", 3) end
	h.i += 1
	return h.store, h.i
end
local function depsChanged(a, b)
	if a == nil or b == nil then return true end
	if #a ~= #b then return true end
	for i = 1, #a do
		if a[i] ~= b[i] then return true end
	end
	return false
end

function LuauUI.useState(initial)
	local store, i = nextSlot()
	local slot = store[i]
	if not slot then
		if type(initial) == "function" then initial = initial() end
		slot = { value = initial }
		slot.set = function(v)
			if type(v) == "function" then v = v(slot.value) end
			if v ~= slot.value then
				slot.value = v
				markDirty()
			end
		end
		store[i] = slot
	end
	return slot.value, slot.set
end
function LuauUI.useReducer(reducer, initial, init)
	local store, i = nextSlot()
	local slot = store[i]
	if not slot then
		slot = { value = init and init(initial) or initial }
		slot.dispatch = function(action)
			local v = reducer(slot.value, action)
			if v ~= slot.value then
				slot.value = v
				markDirty()
			end
		end
		store[i] = slot
	end
	return slot.value, slot.dispatch
end
function LuauUI.useRef(initial)
	local store, i = nextSlot()
	if not store[i] then store[i] = { current = initial } end
	return store[i]
end
function LuauUI.useMemo(fn, deps)
	local store, i = nextSlot()
	local slot = store[i]
	if not slot or depsChanged(slot.deps, deps) then
		slot = { value = fn(), deps = deps }
		store[i] = slot
	end
	return slot.value
end
function LuauUI.useCallback(fn, deps)
	return LuauUI.useMemo(function() return fn end, deps)
end
function LuauUI.useEffect(fn, deps)
	local store, i = nextSlot()
	local slot = store[i]
	if not slot then
		slot = {}
		store[i] = slot
	end
	if slot.ran == nil or depsChanged(slot.deps, deps) then
		slot.deps = deps
		slot.ran = true
		table.insert(pendingEffects, function()
			if type(slot.cleanup) == "function" then pcall(slot.cleanup) end
			slot.cleanup = fn()
		end)
	end
end
LuauUI.useLayoutEffect = LuauUI.useEffect
LuauUI.useInsertionEffect = LuauUI.useEffect
function LuauUI.useContext(ctx) return readContext(ctx) end
function LuauUI.useBinding(initial)
	local store, i = nextSlot()
	if not store[i] then
		local b, set = LuauUI.createBinding(initial)
		store[i] = { b = b, set = set }
	end
	return store[i].b, store[i].set
end
function LuauUI.useId()
	local store, i = nextSlot()
	if not store[i] then store[i] = { id = "luauui-" .. tostring(math.random(1, 1e9)) } end
	return store[i].id
end

-- Class components (Roact style)
local Component = { __isClass = true }
Component.__index = Component
function Component:extend(name)
	local class = {}
	class.__index = class
	class.__isClass = true
	class.__componentName = name
	return setmetatable(class, { __index = self, __tostring = function() return name end })
end
function Component:setState(partial)
	if type(partial) == "function" then partial = partial(self.state, self.props) end
	if type(partial) ~= "table" then return end
	local changed = false
	local ns = table.clone(self.state or {})
	for k, v in pairs(partial) do
		if v == LuauUI.None then v = nil end
		if ns[k] ~= v then
			ns[k] = v
			changed = true
		end
	end
	self.state = ns
	if changed then markDirty() end
end
function Component:render() return nil end
LuauUI.Component = Component
LuauUI.PureComponent = Component

-- Mounting (Roact.mount / ReactRoblox.createRoot) => preview roots
local mountedRoots = {}
function LuauUI.mount(element, _parent, key)
	local handle = { element = element, key = key }
	table.insert(mountedRoots, handle)
	markDirty()
	return handle
end
function LuauUI.update(handle, element)
	handle.element = element
	markDirty()
	return handle
end
function LuauUI.unmount(handle)
	local i = table.find(mountedRoots, handle)
	if i then table.remove(mountedRoots, i) end
	markDirty()
end
function LuauUI.createRoot(_container)
	local handle = { element = nil }
	table.insert(mountedRoots, handle)
	return {
		render = function(_, element)
			handle.element = element
			markDirty()
		end,
		unmount = function()
			handle.element = nil
			markDirty()
		end,
	}
end
LuauUI.createBlockingRoot = LuauUI.createRoot
LuauUI.createLegacyRoot = LuauUI.createRoot
function LuauUI.createPortal(children, _target)
	return LuauUI.createElement(LuauUI.Fragment, nil, children)
end
function LuauUI.act(fn) fn() end

-- Libraries resolvable by name
local LIBS = {
	LuauUI = LuauUI, React = LuauUI, Roact = LuauUI, ReactRoblox = LuauUI, ["react-roblox"] = LuauUI,
	RoactRodux = nil,
}
_G.LuauUI = LuauUI
_G.React = LuauUI
_G.Roact = LuauUI
_G.ReactRoblox = LuauUI
Packages = setmetatable({}, {
	__index = function(_, k)
		local lib = LIBS[k]
		if lib then return lib end
		return serviceProxy("Packages")[k]
	end,
})

----------------------------------------------------------------------
-- Serialization
----------------------------------------------------------------------
local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end

local function normalize(v)
	local tv = type(v)
	if tv == "number" then return finite(v) and v or nil end
	if tv == "string" or tv == "boolean" then return v end
	if tv ~= "table" then return nil end
	if isBinding(v) then return normalize(v:getValue()) end
	local t = rawget(v, "__t")
	if t == "UDim" then return { t = "UDim", s = v.Scale, o = v.Offset } end
	if t == "UDim2" then return { t = "UDim2", xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset } end
	if t == "Vector2" then return { t = "V2", x = v.X, y = v.Y } end
	if t == "Color3" then return { t = "C3", r = v.R, g = v.G, b = v.B } end
	if t == "ColorSequence" then
		local k = {}
		for i, kp in ipairs(v.Keypoints) do
			k[i] = { t = kp.Time, r = kp.Value.R, g = kp.Value.G, b = kp.Value.B }
		end
		return { t = "CS", k = k }
	end
	if t == "NumberSequence" then
		local k = {}
		for i, kp in ipairs(v.Keypoints) do
			k[i] = { t = kp.Time, v = kp.Value }
		end
		return { t = "NS", k = k }
	end
	if t == "EnumItem" then return { t = "E", e = v.EnumType, n = v.Name } end
	if t == "Font" then
		return { t = "Font", f = v.Family, w = v.Weight and v.Weight.Name or "Regular", s = v.Style and v.Style.Name or "Normal", fe = v.FromEnum }
	end
	if t == "Rect" then return { t = "Rect", x0 = v.Min.X, y0 = v.Min.Y, x1 = v.Max.X, y1 = v.Max.Y } end
	if t == "NumberRange" then return { t = "NR", min = v.Min, max = v.Max } end
	return nil
end

local eventRegistry = {}
local eventCount = 0
local function registerEvent(entry)
	eventCount += 1
	eventRegistry[eventCount] = entry
	return eventCount
end

local function serializeInstance(inst)
	local d = INST[inst]
	local node = { c = d.ClassName, n = d.Name, p = {}, k = {}, ev = {} }
	for k, v in pairs(d.props) do
		if type(k) == "string" then
			local nv = normalize(v)
			if nv ~= nil then node.p[k] = nv end
		end
	end
	for name, sig in pairs(d.signals) do
		if #sig._h > 0 then
			node.ev[name] = registerEvent({ kind = "instance", inst = inst, signal = sig, name = name })
		end
	end
	local textSig = d.propSignals.Text
	if textSig and #textSig._h > 0 then
		node.ev["Change:Text"] = registerEvent({ kind = "instance", inst = inst, signal = textSig, name = "Change:Text" })
	end
	for i, c in ipairs(d.children) do
		node.k[i] = serializeInstance(c)
	end
	return node
end

-- Element rendering ---------------------------------------------------
local classInstances = {}
local seenPaths = {}

local function rbxStub(node)
	return setmetatable({ Name = node.n, ClassName = node.c, Text = node.p.Text }, {
		__index = function(_, k)
			if k == "AbsoluteSize" or k == "AbsolutePosition" then return Vector2.new() end
			if Methods[k] then return function() return nil end end
			return nil
		end,
	})
end

local renderElement

local function renderChildren(children, path, out)
	if children == nil then return end
	if isElement(children) then
		renderElement(children, path .. "/1", out, nil)
		return
	end
	if type(children) ~= "table" then return end
	-- keep a stable order: array part first, then string keys sorted
	local keys = {}
	for k in pairs(children) do table.insert(keys, k) end
	table.sort(keys, function(a, b)
		local ta, tb = type(a), type(b)
		if ta ~= tb then return ta == "number" end
		return a < b
	end)
	for _, k in ipairs(keys) do
		local child = children[k]
		renderElement(child, path .. "/" .. tostring(k), out, type(k) == "string" and k or nil)
	end
end

local function withHooks(path, fn)
	local store = hookStore[path]
	if not store then
		store = {}
		hookStore[path] = store
	end
	seenPaths[path] = true
	local prev = currentHooks
	currentHooks = { store = store, i = 0 }
	local ok, res = pcall(fn)
	currentHooks = prev
	if not ok then error(res, 0) end
	return res
end

local function propsWithChildren(el)
	local props = el.props or {}
	if el.children ~= nil and props.children == nil and props[LuauUI.Children] == nil then
		props = table.clone(props)
		props.children = el.children
		props[LuauUI.Children] = el.children
	end
	return props
end

renderElement = function(el, path, out, nameHint)
	if el == nil or el == false or el == true then return end
	if type(el) ~= "table" then return end
	if isBinding(el) then
		renderElement(el:getValue(), path, out, nameHint)
		return
	end
	if not isElement(el) then
		-- plain table of elements (fragment-like)
		renderChildren(el, path, out)
		return
	end
	local comp = el.component
	if type(comp) == "function" then
		local props = propsWithChildren(el)
		local res = withHooks(path, function() return comp(props) end)
		renderElement(res, path .. "/~", out, nameHint)
	elseif type(comp) == "table" and comp.__isClass then
		local inst = classInstances[path]
		local props = propsWithChildren(el)
		if comp.defaultProps then
			local merged = table.clone(comp.defaultProps)
			for k, v in pairs(props) do merged[k] = v end
			props = merged
		end
		if not inst or getmetatable(inst) ~= comp then
			inst = setmetatable({ props = props, state = {} }, comp)
			if inst.init then inst:init(props) end
			classInstances[path] = inst
			if inst.didMount then
				table.insert(pendingEffects, function() inst:didMount() end)
			end
		end
		inst.props = props
		seenPaths[path] = true
		if comp.getDerivedStateFromProps then
			local d = comp.getDerivedStateFromProps(props, inst.state)
			if type(d) == "table" then
				for k, v in pairs(d) do inst.state[k] = v end
			end
		end
		local res = inst:render()
		renderElement(res, path .. "/~", out, nameHint)
	elseif type(comp) == "table" and comp.__fragment then
		renderChildren(el.children or el.props.children or el.props[LuauUI.Children], path, out)
	elseif type(comp) == "table" and comp.__provider then
		table.insert(contextStack, { ctx = comp.__provider, value = el.props.value })
		renderChildren(el.children or el.props.children or el.props[LuauUI.Children], path, out)
		table.remove(contextStack)
	elseif type(comp) == "table" and comp.__consumer then
		local fn = el.props.render or (type(el.children) == "function" and el.children)
		if fn then renderElement(fn(readContext(comp.__consumer)), path .. "/~", out, nameHint) end
	elseif type(comp) == "string" then
		local node = { c = comp, n = nameHint or comp, p = {}, k = {}, ev = {} }
		local childrenFromProps = nil
		local refObj = nil
		for key, val in pairs(el.props) do
			if type(key) == "string" then
				if key == "children" then
					childrenFromProps = val
				elseif key == "Name" then
					node.n = tostring(val)
				elseif key == "ref" then
					refObj = val
				elseif key == "key" then
					-- ignored
				elseif type(val) == "function" then
					-- React-lua style event props: onActivated / Event names passed as strings
					local evName = key:match("^on(%u%w+)$") or (EVENT_NAMES[key] and key)
					if evName then
						node.ev[evName] = registerEvent({ kind = "element", fn = val, node = node, name = evName })
					end
				elseif val ~= LuauUI.None then
					local nv = normalize(val)
					if nv ~= nil then node.p[key] = nv end
				end
			elseif type(key) == "table" then
				if key.__eventKey then
					node.ev[key.__eventKey] = registerEvent({ kind = "element", fn = val, node = node, name = key.__eventKey })
				elseif key.__changeKey then
					node.ev["Change:" .. key.__changeKey] = registerEvent({ kind = "element", fn = val, node = node, name = "Change:" .. key.__changeKey })
				elseif key == LuauUI.Children then
					childrenFromProps = val
				elseif key == LuauUI.Ref then
					refObj = val
				end
			end
		end
		if type(refObj) == "table" then
			refObj.current = rbxStub(node)
		elseif type(refObj) == "function" then
			pcall(refObj, rbxStub(node))
		end
		local kids = el.children
		if kids == nil then kids = childrenFromProps end
		renderChildren(kids, path, node.k)
		table.insert(out, node)
	elseif isInstance(comp) then
		table.insert(out, serializeInstance(comp))
	end
end

----------------------------------------------------------------------
-- require
----------------------------------------------------------------------
local moduleCache = {}
local loading = {}
local currentFile = HOST.file

local function makeEnv(filePath)
	local noExt = string.gsub(filePath, "%.luau?$", "")
	local isInit = string.match(noExt, "/init$") ~= nil
	local base = isInit and parentDir(noExt) or noExt
	local name = string.match(base, "([^/]+)$") or base
	local env = setmetatable({ script = pathProxy({ base }, name) }, { __index = _G })
	return env
end

local function loadModule(absPath)
	local cached = moduleCache[absPath]
	if cached ~= nil then return cached.value end
	if loading[absPath] then error("circular require: " .. absPath, 3) end
	loading[absPath] = true
	local fn = HOST.load(absPath)
	setfenv(fn, makeEnv(absPath))
	local co = coroutine.create(fn)
	local ok, res = coroutine.resume(co)
	loading[absPath] = nil
	if not ok then error(debug.traceback(co, tostring(res)), 0) end
	if coroutine.status(co) ~= "dead" then
		error("Module " .. absPath .. " yielded (task.wait) while loading", 3)
	end
	moduleCache[absPath] = { value = res }
	return res
end

local function callerDir()
	-- best effort: the file being executed by the caller
	local info = debug.info(3, "s")
	if type(info) == "string" then
		local p = string.match(info, "^@?(.+)$")
		if p and HOST.isfile(p) then return parentDir(p) end
	end
	return parentDir(currentFile)
end

require = function(target)
	if type(target) == "table" then
		if rawget(target, "__lib") then return target end
		if rawget(target, "__proxy") then
			local bases = rawget(target, "__bases")
			for _, b in ipairs(bases) do
				local found = HOST.find(b)
				if found then return loadModule(found) end
			end
			local name = rawget(target, "__name")
			if LIBS[name] then return LIBS[name] end
			error("Module not found: " .. tostring(name) .. " (searched: " .. table.concat(bases, ", ") .. ")", 2)
		end
		if isInstance(target) then
			error("require(Instance) is not supported in the preview: use script.Parent.X or a \"./X\" path", 2)
		end
	elseif type(target) == "string" then
		if LIBS[target] then return LIBS[target] end
		local s = target
		local base
		if s:sub(1, 1) == "@" then
			local alias, rest = s:match("^@([^/]+)/?(.*)$")
			if LIBS[rest] then return LIBS[rest] end
			if alias == "self" then
				base = string.gsub(currentFile, "%.luau?$", "")
				s = rest
			else
				base = ROOT
				s = (alias == "game" or alias == "project") and rest or (alias .. "/" .. rest)
			end
		else
			base = callerDir()
		end
		local found = HOST.find(base .. "/" .. s)
		if found then return loadModule(found) end
		local last = s:match("([^/]+)$")
		if last and LIBS[last] then return LIBS[last] end
		error("Module not found: \"" .. target .. "\" from " .. base, 2)
	elseif type(target) == "number" then
		error("require(assetId) is not supported in the preview", 2)
	end
	error("Invalid require argument: " .. tostring(target), 2)
end

----------------------------------------------------------------------
-- Entry points called by the host
----------------------------------------------------------------------
local moduleResult = nil
local moduleYielded = false

function __luauui_load()
	moduleResult = nil
	local fn = HOST.load(currentFile)
	setfenv(fn, makeEnv(currentFile))
	local co = coroutine.create(fn)
	local ok, res = coroutine.resume(co)
	if not ok then error(debug.traceback(co, tostring(res)), 0) end
	moduleYielded = coroutine.status(co) ~= "dead"
	if not moduleYielded then moduleResult = res end
	moduleCache[currentFile] = { value = res }
end

local function rootElement()
	local r = moduleResult
	if type(r) == "function" then
		return LuauUI.createElement(r, {})
	end
	if isElement(r) then return r end
	if type(r) == "table" and rawget(r, "__isClass") then
		return LuauUI.createElement(r, {})
	end
	if type(r) == "table" and not isInstance(r) and not rawget(r, "__t") then
		local story = r.story or r.Story or r.render or r.Render or r.Component or r.App
		if type(story) == "function" then
			return LuauUI.createElement(story, r.props or {})
		end
		if isElement(story) then return story end
		if type(story) == "table" and story.__isClass then
			return LuauUI.createElement(story, r.props or {})
		end
	end
	return nil
end

local function renderOnce()
	eventRegistry = {}
	eventCount = 0
	seenPaths = {}
	contextStack = {}
	pendingEffects = {}
	local roots = {}
	local r = moduleResult
	local el = rootElement()
	if el then
		renderElement(el, "root", roots, string.match(currentFile, "([^/]+)%.luau?$"))
	elseif isInstance(r) then
		table.insert(roots, serializeInstance(r))
	end
	for i, h in ipairs(mountedRoots) do
		if h.element then renderElement(h.element, "mount" .. i, roots, h.key) end
	end
	for _, container in ipairs({ playerGui, starterGui }) do
		for _, c in ipairs(INST[container].children) do
			if c ~= r then table.insert(roots, serializeInstance(c)) end
		end
	end
	-- drop state of unmounted components
	for p in pairs(hookStore) do
		if not seenPaths[p] then hookStore[p] = nil end
	end
	for p, inst in pairs(classInstances) do
		if not seenPaths[p] then
			if inst.willUnmount then pcall(inst.willUnmount, inst) end
			classInstances[p] = nil
		end
	end
	return roots
end

function __luauui_render()
	local roots
	for _ = 1, 8 do
		dirty = false
		roots = renderOnce()
		local effects = pendingEffects
		pendingEffects = {}
		for _, fx in ipairs(effects) do
			safeCall(fx)
		end
		if not dirty then break end
	end
	return { roots = roots, yielded = moduleYielded, events = eventCount }
end

function __luauui_fire(id, payload)
	local entry = eventRegistry[id]
	if not entry then return false end
	payload = payload or {}
	local name = entry.name
	if entry.kind == "instance" then
		local inst = entry.inst
		if payload.text ~= nil then
			INST[inst].props.Text = payload.text
		end
		if name == "FocusLost" then
			entry.signal:Fire(payload.enter == true)
		elseif name == "Change:Text" or name == "Changed" then
			entry.signal:Fire(name == "Changed" and "Text" or nil)
		elseif name == "Activated" or name == "InputBegan" or name == "InputEnded" then
			entry.signal:Fire({ UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Enum.UserInputState.End, Position = Vector3.new() }, 1)
		else
			entry.signal:Fire()
		end
	else
		local node = entry.node
		if payload.text ~= nil then node.p.Text = payload.text end
		local rbx = rbxStub(node)
		if name == "FocusLost" then
			safeCall(entry.fn, rbx, payload.enter == true)
		else
			safeCall(entry.fn, rbx, { UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Enum.UserInputState.End, Position = Vector3.new() }, 1)
		end
	end
	return true
end
