local LuauUI = require(Packages.LuauUI)
local Theme = require(script.Parent._shared.Theme)
local e = LuauUI.createElement

local function Counter(props)
	return e("Frame", {
		Size = UDim2.fromOffset(170, 44),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		LayoutOrder = props.order,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Gradient = e("UIGradient", { Color = Theme.coal(), Rotation = 90 }),
		Stroke = e("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.8, Thickness = 1.5 }),
		Icon = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 6, 0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(props.round and 1 or 0.3, 0) }),
			Gradient = e("UIGradient", { Color = Theme.ink(), Rotation = 135 }),
		}),
		Amount = e("TextLabel", {
			Position = UDim2.fromOffset(46, 0),
			Size = UDim2.new(1, -56, 1, 0),
			BackgroundTransparency = 1,
			Text = props.text,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.fontBlack,
			TextSize = 20,
		}, {
			Gradient = e("UIGradient", { Color = Theme.ink(), Rotation = 90 }),
		}),
	})
end

return function()
	return e("ScreenGui", { IgnoreGuiInset = false, DisplayOrder = 1 }, {
		Bar = e("Frame", {
			Position = UDim2.fromOffset(20, 16),
			Size = UDim2.new(0, 400, 0, 44),
			BackgroundTransparency = 1,
		}, {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Coins = e(Counter, { text = "12 480", round = true, order = 1 }),
			Gems = e(Counter, { text = "320", round = false, order = 2 }),
		}),
	})
end
