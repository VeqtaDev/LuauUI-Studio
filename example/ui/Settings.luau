-- Imperative style: Instance.new + :Connect, like a classic LocalScript.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Theme = require(script.Parent._shared.Theme)

local gui = Instance.new("ScreenGui")
gui.Name = "Settings"
gui.DisplayOrder = 4

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Position = UDim2.fromOffset(20, 76)
panel.Size = UDim2.fromOffset(280, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = Color3.new(1, 1, 1)
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 20)
corner.Parent = panel

local gradient = Instance.new("UIGradient")
gradient.Color = Theme.coal()
gradient.Rotation = 90
gradient.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 16)
padding.PaddingBottom = UDim.new(0, 16)
padding.PaddingLeft = UDim.new(0, 18)
padding.PaddingRight = UDim.new(0, 18)
padding.Parent = panel

local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 12)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = 0
title.Size = UDim2.new(1, 0, 0, 28)
title.BackgroundTransparency = 1
title.Text = "Réglages"
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.FontFace = Theme.fontBlack
title.TextSize = 22
title.Parent = panel

local function makeToggle(label, order, initial)
	local row = Instance.new("Frame")
	row.Name = label
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 30)
	row.BackgroundTransparency = 1

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Size = UDim2.new(1, -60, 1, 0)
	text.BackgroundTransparency = 1
	text.Text = label
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.fromRGB(220, 220, 220)
	text.FontFace = Theme.font
	text.TextSize = 16
	text.Parent = row

	local switch = Instance.new("TextButton")
	switch.Name = "Switch"
	switch.AnchorPoint = Vector2.new(1, 0.5)
	switch.Position = UDim2.fromScale(1, 0.5)
	switch.Size = UDim2.fromOffset(52, 30)
	switch.Text = ""
	switch.BackgroundColor3 = Color3.new(1, 1, 1)
	switch.BorderSizePixel = 0
	switch.Parent = row

	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(1, 0)
	sc.Parent = switch

	local sg = Instance.new("UIGradient")
	sg.Rotation = 90
	sg.Parent = switch

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0, 0.5)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BorderSizePixel = 0
	knob.Parent = switch

	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(1, 0)
	kc.Parent = knob

	local kg = Instance.new("UIGradient")
	kg.Rotation = 90
	kg.Parent = knob

	local on = initial
	local function apply()
		sg.Color = on and Theme.ink() or Theme.steel()
		kg.Color = on and Theme.coal() or Theme.ink()
		TweenService:Create(knob, TweenInfo.new(0.2), {
			Position = on and UDim2.new(1, -27, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		}):Play()
	end
	apply()

	switch.Activated:Connect(function()
		on = not on
		apply()
		print(label, on and "activé" or "désactivé")
	end)

	row.Parent = panel
	return row
end

makeToggle("Musique", 1, true)
makeToggle("Effets sonores", 2, false)
makeToggle("Ombres", 3, true)

local nameBox = Instance.new("TextBox")
nameBox.Name = "Pseudo"
nameBox.LayoutOrder = 4
nameBox.Size = UDim2.new(1, 0, 0, 40)
nameBox.BackgroundColor3 = Color3.new(1, 1, 1)
nameBox.BorderSizePixel = 0
nameBox.PlaceholderText = "Pseudo affiché…"
nameBox.Text = Players.LocalPlayer.DisplayName
nameBox.TextColor3 = Color3.new(0, 0, 0)
nameBox.FontFace = Theme.font
nameBox.TextSize = 16
nameBox.Parent = panel

local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(0, 12)
bc.Parent = nameBox

local bg = Instance.new("UIGradient")
bg.Color = Theme.ink()
bg.Rotation = 90
bg.Parent = nameBox

nameBox.FocusLost:Connect(function(enter)
	title.Text = "Réglages · " .. nameBox.Text
end)

return gui
