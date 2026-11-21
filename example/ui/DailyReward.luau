-- Roact-style class component
local Roact = require(game.ReplicatedStorage.Packages.Roact)
local Theme = require(script.Parent._shared.Theme)
local e = Roact.createElement

local DailyReward = Roact.Component:extend("DailyReward")

function DailyReward:init()
	self.state = { day = 4, claimed = false }
end

function DailyReward:render()
	local cells = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i = 1, 7 do
		local done = i < self.state.day or (i == self.state.day and self.state.claimed)
		local today = i == self.state.day
		cells["Day" .. i] = e("TextLabel", {
			LayoutOrder = i,
			Size = UDim2.new(1 / 7, -6, 1, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Text = tostring(i),
			TextColor3 = done and Color3.new(1, 1, 1) or Color3.new(0, 0, 0),
			FontFace = Theme.fontBlack,
			TextSize = 14,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Gradient = e("UIGradient", {
				Color = done and Theme.coal() or (today and Theme.ink() or Theme.steel()),
				Rotation = 90,
			}),
		})
	end

	return e("ScreenGui", { DisplayOrder = 3 }, {
		Card = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -24, 0, 16),
			Size = UDim2.fromOffset(300, 176),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 22) }),
			Gradient = e("UIGradient", { Color = Theme.ink(), Rotation = 90 }),
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 16),
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
				PaddingBottom = UDim.new(0, 16),
			}),
			Title = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				Text = "Récompense du jour",
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = Color3.new(0, 0, 0),
				FontFace = Theme.fontBlack,
				TextSize = 20,
			}),
			Days = e("Frame", {
				Position = UDim2.fromOffset(0, 38),
				Size = UDim2.new(1, 6, 0, 34),
				BackgroundTransparency = 1,
			}, cells),
			Claim = e("TextButton", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 44),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Text = self.state.claimed and "Reviens demain" or "Récupérer 150 pièces",
				TextColor3 = Color3.new(1, 1, 1),
				FontFace = Theme.fontBlack,
				TextSize = 16,
				[Roact.Event.Activated] = function()
					if not self.state.claimed then
						self:setState({ claimed = true })
					end
				end,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = e("UIGradient", { Color = Theme.coal(), Rotation = 90 }),
			}),
		}),
	})
end

return DailyReward
