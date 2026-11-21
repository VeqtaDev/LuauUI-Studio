--[[
	Boutique — black & white, strong gradients, stud texture (ui-resources.com).
	Categories on the left, item grid in the middle, details + purchase on the right.
]]
local LuauUI = require(Packages.LuauUI)
local Theme = require("./_shared/Theme")
local e = LuauUI.createElement

local camera = workspace.CurrentCamera

----------------------------------------------------------------------
-- Data
----------------------------------------------------------------------
local RARITY = {
	Commun = { order = 1, label = "COMMUN" },
	Rare = { order = 2, label = "RARE" },
	Epique = { order = 3, label = "ÉPIQUE" },
	Legendaire = { order = 4, label = "LÉGENDAIRE" },
}

local ITEMS = {
	{ id = "onyx", cat = "Armes", kind = "weapon", name = "Lame d'Onyx", rarity = "Legendaire", price = 4800,
		desc = "Forgée dans la pierre noire. Chaque coup laisse une traînée d'ombre.", stats = { 0.95, 0.7, 0.55 } },
	{ id = "frost", cat = "Armes", kind = "weapon", name = "Katana Givre", rarity = "Epique", price = 2400,
		desc = "Une lame fine et rapide, froide comme un matin d'hiver.", stats = { 0.7, 0.92, 0.4 } },
	{ id = "hammer", cat = "Armes", kind = "weapon", name = "Marteau Lourd", rarity = "Rare", price = 1200,
		desc = "Lent, mais chaque impact fait trembler le sol.", stats = { 0.85, 0.25, 0.8 } },
	{ id = "dagger", cat = "Armes", kind = "weapon", name = "Dague", rarity = "Commun", price = 300,
		desc = "Simple et fiable. Parfaite pour débuter.", stats = { 0.35, 0.75, 0.3 } },
	{ id = "raven", cat = "Familiers", kind = "pet", name = "Corbeau", rarity = "Legendaire", price = 5200,
		desc = "Il vole devant toi et repère les coffres cachés.", stats = { 0.6, 0.9, 0.95 } },
	{ id = "golem", cat = "Familiers", kind = "pet", name = "Golem", rarity = "Epique", price = 2600,
		desc = "Un petit gardien de pierre qui encaisse pour toi.", stats = { 0.5, 0.2, 0.95 } },
	{ id = "ghost", cat = "Familiers", kind = "pet", name = "Spectre", rarity = "Rare", price = 1400,
		desc = "Traverse les murs. Personne ne sait d'où il vient.", stats = { 0.4, 0.8, 0.5 } },
	{ id = "kitten", cat = "Familiers", kind = "pet", name = "Chaton", rarity = "Commun", price = 450,
		desc = "Il ne sert à rien, mais il est adorable.", stats = { 0.15, 0.6, 0.3 } },
	{ id = "eclipse", cat = "Effets", kind = "effect", name = "Aura Éclipse", rarity = "Legendaire", price = 6000,
		desc = "Un halo noir et blanc qui pulse autour de toi.", stats = { 0.3, 0.5, 1 } },
	{ id = "neon", cat = "Effets", kind = "effect", name = "Traînée Néon", rarity = "Epique", price = 2200,
		desc = "Une ligne lumineuse suit chacun de tes pas.", stats = { 0.2, 0.9, 0.7 } },
	{ id = "halo", cat = "Effets", kind = "effect", name = "Halo", rarity = "Rare", price = 900,
		desc = "Un anneau discret au-dessus de la tête.", stats = { 0.1, 0.4, 0.6 } },
	{ id = "smoke", cat = "Effets", kind = "effect", name = "Fumée", rarity = "Commun", price = 250,
		desc = "Un petit nuage gris quand tu sautes.", stats = { 0.1, 0.3, 0.3 } },
}

local CATEGORIES = {
	{ id = "Vedettes", icon = "star" },
	{ id = "Armes", icon = "weapon" },
	{ id = "Familiers", icon = "pet" },
	{ id = "Effets", icon = "effect" },
}

local FEATURED = { "onyx", "raven", "eclipse", "frost" }
local DEAL = { id = "onyx", discount = 0.3 }

local byId = {}
for _, it in ITEMS do
	byId[it.id] = it
end

local function priceOf(item)
	if item.id == DEAL.id then
		return math.floor(item.price * (1 - DEAL.discount) / 10) * 10
	end
	return item.price
end

local function fmt(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end

----------------------------------------------------------------------
-- Small building blocks
----------------------------------------------------------------------
local function corner(r)
	return e("UICorner", { CornerRadius = r or UDim.new(0, 16) })
end

local function grad(seq, rot, transparency)
	return e("UIGradient", { Color = seq, Rotation = rot or 90, Transparency = transparency })
end

local function stroke(t, transparency)
	return e("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Thickness = t or 1.5,
		Transparency = transparency or 0.8,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

-- Tiled stud texture laid over a surface (ZIndex 0 keeps it behind siblings)
local function Studs(props)
	return e("ImageLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = Theme.studTexture,
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(props.tile or 64, props.tile or 64),
		ImageTransparency = props.transparency or 0.93,
		ZIndex = 0,
	}, {
		Corner = corner(UDim.new(0, props.radius or 0)),
	})
end

local function Label(props)
	return e("TextLabel", {
		AnchorPoint = props.anchor,
		Position = props.pos,
		Size = props.size or UDim2.new(1, 0, 0, props.textSize or 16),
		AutomaticSize = props.auto,
		BackgroundTransparency = 1,
		Text = props.text,
		RichText = props.rich,
		TextColor3 = props.color or Color3.new(1, 1, 1),
		TextTransparency = props.transparency,
		TextSize = props.textSize or 16,
		FontFace = props.font or Theme.font,
		TextXAlignment = props.align or Enum.TextXAlignment.Left,
		TextYAlignment = props.valign,
		TextWrapped = props.wrap,
		LayoutOrder = props.order,
		ZIndex = props.z,
	}, props.gradient and { Gradient = grad(props.gradient, 90) } or nil)
end

local function StudIcon(props)
	return e("ImageLabel", {
		AnchorPoint = props.anchor,
		Position = props.pos,
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Image = Theme.studIcon,
		ScaleType = Enum.ScaleType.Crop,
		LayoutOrder = props.order,
	}, {
		Corner = corner(UDim.new(0.28, 0)),
		Gradient = grad(Theme.ink(), 90),
		Stroke = e("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.6 }),
	})
end

----------------------------------------------------------------------
-- Emblems (item art built from frames: no external images needed)
----------------------------------------------------------------------
local function part(props)
	return e("Frame", {
		AnchorPoint = props.anchor or Vector2.new(0.5, 0.5),
		Position = props.pos,
		Size = props.size,
		Rotation = props.rot,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = props.transparency or 0,
		BorderSizePixel = 0,
		ZIndex = props.z or 1,
	}, {
		Corner = props.radius and corner(props.radius) or nil,
		Gradient = grad(props.seq or Theme.ink(), props.gradRot or 90),
		Stroke = props.ring and e("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = props.ring, Transparency = props.ringT or 0 }) or nil,
	})
end

local function Emblem(props)
	local kind = props.kind
	local strong = props.rarity == "Legendaire" or props.rarity == "Epique"
	local main = strong and Theme.chrome() or Theme.ink()
	local dark = Theme.coal()
	local children = {}

	if kind == "weapon" then
		children.Blade = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Rotation = 45,
			BackgroundTransparency = 1,
		}, {
			Edge = part({ pos = UDim2.fromScale(0.5, 0.33), size = UDim2.fromScale(0.15, 0.56), seq = main, gradRot = 0, radius = UDim.new(0.5, 0) }),
			Tip = part({ pos = UDim2.fromScale(0.5, 0.07), size = UDim2.fromScale(0.106, 0.106), rot = 45, seq = main, radius = UDim.new(0, 2) }),
			Guard = part({ pos = UDim2.fromScale(0.5, 0.64), size = UDim2.fromScale(0.46, 0.075), seq = dark, radius = UDim.new(1, 0), ring = 2, ringT = 0.4 }),
			Grip = part({ pos = UDim2.fromScale(0.5, 0.77), size = UDim2.fromScale(0.09, 0.2), seq = Theme.steel(), radius = UDim.new(0.5, 0) }),
			Pommel = part({ pos = UDim2.fromScale(0.5, 0.89), size = UDim2.fromScale(0.13, 0.13), seq = main, radius = UDim.new(1, 0) }),
		})
	elseif kind == "pet" then
		children.EarL = part({ pos = UDim2.fromScale(0.3, 0.3), size = UDim2.fromScale(0.22, 0.22), rot = 45, seq = main, radius = UDim.new(0.2, 0) })
		children.EarR = part({ pos = UDim2.fromScale(0.7, 0.3), size = UDim2.fromScale(0.22, 0.22), rot = 45, seq = main, radius = UDim.new(0.2, 0) })
		children.Head = part({ pos = UDim2.fromScale(0.5, 0.56), size = UDim2.fromScale(0.64, 0.6), seq = main, radius = UDim.new(0.48, 0) })
		children.EyeL = part({ pos = UDim2.fromScale(0.39, 0.54), size = UDim2.fromScale(0.1, 0.13), seq = dark, radius = UDim.new(1, 0), z = 2 })
		children.EyeR = part({ pos = UDim2.fromScale(0.61, 0.54), size = UDim2.fromScale(0.1, 0.13), seq = dark, radius = UDim.new(1, 0), z = 2 })
		children.Nose = part({ pos = UDim2.fromScale(0.5, 0.67), size = UDim2.fromScale(0.08, 0.05), seq = dark, radius = UDim.new(1, 0), z = 2 })
	elseif kind == "effect" then
		children.Outer = part({ pos = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.86, 0.86), transparency = 1, radius = UDim.new(1, 0), ring = 3, ringT = 0.65 })
		children.Mid = part({ pos = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.62, 0.62), transparency = 1, radius = UDim.new(1, 0), ring = 5, ringT = 0.3 })
		children.Core = part({ pos = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.34, 0.34), seq = main, radius = UDim.new(1, 0) })
		children.Spark = part({ pos = UDim2.fromScale(0.78, 0.24), size = UDim2.fromScale(0.1, 0.1), rot = 45, seq = main, radius = UDim.new(0, 2) })
	else -- star
		children.A = part({ pos = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.5, 0.5), rot = 45, seq = main, radius = UDim.new(0.12, 0) })
		children.B = part({ pos = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.5, 0.5), seq = main, radius = UDim.new(0.12, 0) })
		children.C = part({ pos = UDim2.fromScale(0.5, 0.5), size = UDim2.fromScale(0.2, 0.2), seq = dark, radius = UDim.new(1, 0) })
	end

	return e("Frame", {
		AnchorPoint = props.anchor or Vector2.new(0.5, 0.5),
		Position = props.pos or UDim2.fromScale(0.5, 0.5),
		Size = props.size,
		BackgroundTransparency = 1,
	}, children)
end

-- Round "well" the emblem sits in, with stud texture and a soft glow
local function EmblemWell(props)
	local legendary = props.rarity == "Legendaire"
	return e("Frame", {
		AnchorPoint = props.anchor,
		Position = props.pos,
		Size = props.size,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		Corner = corner(UDim.new(0, props.radius or 22)),
		Gradient = grad(legendary and Theme.steel() or Theme.night(), 135),
		Stroke = stroke(legendary and 2 or 1.5, legendary and 0.35 or 0.82),
		Studs = e(Studs, { tile = props.tile or 40, transparency = 0.9, radius = props.radius or 22 }),
		Glow = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.55),
			Size = UDim2.fromScale(0.85, 0.85),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = legendary and 0.82 or 0.92,
			BorderSizePixel = 0,
		}, {
			Corner = corner(UDim.new(1, 0)),
			Ratio = e("UIAspectRatioConstraint", { AspectRatio = 1 }),
		}),
		Art = e(Emblem, { kind = props.kind, rarity = props.rarity, size = UDim2.fromScale(0.72, 0.72) }),
	})
end

local function RarityTag(props)
	local r = RARITY[props.rarity]
	local bright = props.rarity == "Legendaire" or props.rarity == "Epique"
	return e("TextLabel", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = (props.rarity == "Legendaire" and "★ " or "") .. r.label,
		TextColor3 = bright and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
		FontFace = Theme.fontBlack,
		TextSize = 11,
		LayoutOrder = props.order,
	}, {
		Corner = corner(UDim.new(1, 0)),
		Gradient = grad(bright and Theme.ink() or Theme.steel(), 90),
		Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
end

----------------------------------------------------------------------
-- Sections
----------------------------------------------------------------------
local function CategoryTab(props)
	local active = props.active
	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = active and 0 or 0.94,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = props.order,
		[LuauUI.Event.Activated] = props.onSelect,
	}, {
		Corner = corner(UDim.new(0, 18)),
		Gradient = active and grad(Theme.ink(), 90) or nil,
		Stroke = not active and stroke(1, 0.88) or nil,
		Icon = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(38, 38),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, {
			Corner = corner(UDim.new(0, 12)),
			Gradient = grad(active and Theme.coal() or Theme.steel(), 90),
			Art = e(Emblem, { kind = props.icon, rarity = "Commun", size = UDim2.fromScale(0.74, 0.74) }),
		}),
		Name = Label({
			pos = UDim2.fromOffset(60, 0),
			size = UDim2.new(1, -66, 1, 0),
			text = props.label,
			textSize = 16,
			font = Theme.fontBlack,
			color = active and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
		}),
		Count = Label({
			anchor = Vector2.new(1, 0.5),
			pos = UDim2.new(1, -12, 0.5, 0),
			size = UDim2.fromOffset(30, 20),
			text = tostring(props.count),
			textSize = 12,
			align = Enum.TextXAlignment.Right,
			color = active and Color3.fromRGB(70, 70, 70) or Color3.fromRGB(150, 150, 150),
		}),
	})
end

local function DealBanner(props)
	local item = byId[DEAL.id]
	local newPrice = priceOf(item)
	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, 150),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		[LuauUI.Event.Activated] = props.onSelect,
	}, {
		Corner = corner(UDim.new(0, 24)),
		Gradient = grad(Theme.chrome(), 100),
		Studs = e(Studs, { tile = 52, transparency = 0.78, radius = 24 }),
		Stroke = stroke(2, 0.2),
		Tag = e("TextLabel", {
			Position = UDim2.fromOffset(22, 18),
			Size = UDim2.fromOffset(150, 26),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Text = "OFFRE DU JOUR",
			TextColor3 = Color3.new(1, 1, 1),
			FontFace = Theme.fontBlack,
			TextSize = 12,
		}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.coal(), 90) }),
		Title = Label({
			pos = UDim2.fromOffset(22, 52),
			size = UDim2.new(0.62, 0, 0, 40),
			text = item.name,
			textSize = 34,
			font = Theme.fontBlack,
			color = Color3.new(0, 0, 0),
		}),
		Price = Label({
			pos = UDim2.fromOffset(22, 98),
			size = UDim2.new(0.6, 0, 0, 24),
			rich = true,
			text = string.format('<s><font transparency="0.5">%s</font></s>  %s studs', fmt(item.price), fmt(newPrice)),
			textSize = 18,
			font = Theme.fontBlack,
			color = Color3.fromRGB(20, 20, 20),
		}),
		Timer = Label({
			pos = UDim2.fromOffset(22, 124),
			size = UDim2.new(0.6, 0, 0, 16),
			text = "Se termine dans 02:14:51",
			textSize = 12,
			color = Color3.fromRGB(70, 70, 70),
		}),
		Discount = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -18, 0, 16),
			Size = UDim2.fromOffset(74, 74),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Rotation = 12,
			Text = "-" .. math.floor(DEAL.discount * 100) .. "%",
			TextColor3 = Color3.new(1, 1, 1),
			FontFace = Theme.fontBlack,
			TextSize = 22,
			ZIndex = 3,
		}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.coal(), 90), Stroke = stroke(3, 0) }),
		Art = e(EmblemWell, {
			anchor = Vector2.new(1, 0.5),
			pos = UDim2.new(1, -70, 0.5, 0),
			size = UDim2.fromOffset(118, 118),
			kind = item.kind,
			rarity = item.rarity,
			radius = 26,
		}),
	})
end

local function ItemCard(props)
	local item = props.item
	local selected = props.selected
	local owned = props.owned
	local legendary = item.rarity == "Legendaire"
	return e("TextButton", {
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = true,
		LayoutOrder = props.order,
		[LuauUI.Event.Activated] = props.onSelect,
	}, {
		Corner = corner(UDim.new(0, 22)),
		Gradient = grad(selected and Theme.steel() or Theme.night(), 120),
		Stroke = selected and stroke(3, 0) or stroke(legendary and 2 or 1.5, legendary and 0.55 or 0.85),
		Studs = e(Studs, { tile = 44, transparency = selected and 0.86 or 0.95, radius = 22 }),
		Well = e(EmblemWell, {
			anchor = Vector2.new(0, 0.5),
			pos = UDim2.new(0, 14, 0.5, 0),
			size = UDim2.new(0, 112, 1, -28),
			kind = item.kind,
			rarity = item.rarity,
			radius = 18,
			tile = 30,
		}),
		Info = e("Frame", {
			Position = UDim2.new(0, 140, 0, 16),
			Size = UDim2.new(1, -154, 1, -32),
			BackgroundTransparency = 1,
		}, {
			List = e("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			Rarity = e(RarityTag, { rarity = item.rarity, order = 1 }),
			Name = Label({ text = item.name, textSize = 19, font = Theme.fontBlack, order = 2, size = UDim2.new(1, 0, 0, 24), gradient = Theme.ink() }),
			Kind = Label({ text = item.cat, textSize = 12, order = 3, color = Color3.fromRGB(140, 140, 140), size = UDim2.new(1, 0, 0, 16) }),
		}),
		Price = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 140, 1, -16),
			Size = UDim2.new(1, -154, 0, 30),
			BackgroundTransparency = 1,
		}, owned and {
			Owned = e("TextLabel", {
				Size = UDim2.fromOffset(110, 30),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Text = "✓  POSSÉDÉ",
				TextColor3 = Color3.new(0, 0, 0),
				FontFace = Theme.fontBlack,
				TextSize = 12,
			}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.ink(), 90) }),
		} or {
			Icon = e(StudIcon, { size = 26, anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(0, 0.5) }),
			Amount = Label({
				pos = UDim2.fromOffset(34, 0),
				size = UDim2.new(1, -34, 1, 0),
				text = fmt(priceOf(item)),
				textSize = 20,
				font = Theme.fontBlack,
				gradient = Theme.ink(),
			}),
		}),
	})
end

local function StatBar(props)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = props.order,
	}, {
		Name = Label({ size = UDim2.new(1, 0, 0, 14), text = props.label, textSize = 12, color = Color3.fromRGB(170, 170, 170) }),
		Value = Label({
			anchor = Vector2.new(1, 0),
			pos = UDim2.fromScale(1, 0),
			size = UDim2.fromOffset(40, 14),
			text = tostring(math.floor(props.value * 100)),
			textSize = 12,
			font = Theme.fontBlack,
			align = Enum.TextXAlignment.Right,
		}),
		Track = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
		}, {
			Corner = corner(UDim.new(1, 0)),
			Fill = e("Frame", {
				Size = UDim2.fromScale(math.clamp(props.value, 0.04, 1), 1),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
			}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.ink(), 0) }),
		}),
	})
end

local function Detail(props)
	local item = props.item
	local owned = props.owned
	local equipped = props.equipped
	local price = priceOf(item)
	local canBuy = not owned and props.studs >= price

	local buttonText, buttonSeq, buttonColor
	if equipped then
		buttonText, buttonSeq, buttonColor = "ÉQUIPÉ", Theme.steel(), Color3.fromRGB(235, 235, 235)
	elseif owned then
		buttonText, buttonSeq, buttonColor = "ÉQUIPER", Theme.ink(), Color3.new(0, 0, 0)
	elseif canBuy then
		buttonText, buttonSeq, buttonColor = "ACHETER", Theme.ink(), Color3.new(0, 0, 0)
	else
		buttonText, buttonSeq, buttonColor = "IL MANQUE " .. fmt(price - props.studs), Theme.steel(), Color3.fromRGB(210, 210, 210)
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -24, 0, 112),
		Size = UDim2.new(0, 330, 1, -136),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, {
		Corner = corner(UDim.new(0, 26)),
		Gradient = grad(Theme.night(), 90),
		Stroke = stroke(1.5, 0.8),
		Preview = e(EmblemWell, {
			pos = UDim2.fromOffset(16, 16),
			size = UDim2.new(1, -32, 0, 176),
			kind = item.kind,
			rarity = item.rarity,
			radius = 20,
			tile = 46,
		}),
		Body = e("Frame", {
			Position = UDim2.fromOffset(20, 206),
			Size = UDim2.new(1, -40, 1, -296),
			BackgroundTransparency = 1,
		}, {
			List = e("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
			Rarity = e(RarityTag, { rarity = item.rarity, order = 1 }),
			Name = Label({ text = item.name, textSize = 26, font = Theme.fontBlack, order = 2, size = UDim2.new(1, 0, 0, 30), gradient = Theme.ink() }),
			Desc = Label({
				text = item.desc,
				textSize = 13,
				wrap = true,
				order = 3,
				size = UDim2.new(1, 0, 0, 36),
				color = Color3.fromRGB(175, 175, 175),
				font = Theme.fontMedium,
				valign = Enum.TextYAlignment.Top,
			}),
			Gap = e("Frame", { Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1, LayoutOrder = 4 }),
			Stat1 = e(StatBar, { label = item.kind == "pet" and "Loyauté" or "Puissance", value = item.stats[1], order = 5 }),
			Stat2 = e(StatBar, { label = "Vitesse", value = item.stats[2], order = 6 }),
			Stat3 = e(StatBar, { label = item.kind == "effect" and "Éclat" or "Résistance", value = item.stats[3], order = 7 }),
		}),
		Buy = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -16),
			Size = UDim2.new(1, -32, 0, 62),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = true,
			[LuauUI.Event.Activated] = props.onBuy,
		}, {
			Corner = corner(UDim.new(0, 20)),
			Gradient = grad(buttonSeq, 90),
			Studs = (canBuy or (owned and not equipped)) and e(Studs, { tile = 36, transparency = 0.82, radius = 20 }) or nil,
			Stroke = e("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			Text = Label({
				pos = UDim2.fromOffset(18, 0),
				size = UDim2.new(1, -36, 1, 0),
				text = buttonText,
				textSize = 18,
				font = Theme.fontBlack,
				color = buttonColor,
				align = (canBuy and Enum.TextXAlignment.Left) or Enum.TextXAlignment.Center,
				z = 2,
			}),
			Cost = canBuy and e("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0),
				Size = UDim2.fromOffset(122, 42),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = corner(UDim.new(0, 14)),
				Gradient = grad(Theme.coal(), 90),
				Icon = e(StudIcon, { size = 26, anchor = Vector2.new(0, 0.5), pos = UDim2.new(0, 8, 0.5, 0) }),
				Amount = Label({
					pos = UDim2.fromOffset(40, 0),
					size = UDim2.new(1, -48, 1, 0),
					text = fmt(price),
					textSize = 17,
					font = Theme.fontBlack,
					gradient = Theme.ink(),
				}),
			}) or nil,
		}),
	})
end

----------------------------------------------------------------------
-- Shop
----------------------------------------------------------------------
return function()
	local category, setCategory = LuauUI.useState("Vedettes")
	local selectedId, setSelectedId = LuauUI.useState("onyx")
	local studs, setStuds = LuauUI.useState(6250)
	local owned, setOwned = LuauUI.useState({ dagger = true })
	local equipped, setEquipped = LuauUI.useState({ dagger = true })
	local open, setOpen = LuauUI.useState(true)
	local notice, setNotice = LuauUI.useState(nil)

	local vp = camera.ViewportSize
	local scale = math.min(vp.X / 1320, vp.Y / 800, 1.25)

	if not open then
		return e("ScreenGui", { IgnoreGuiInset = true, DisplayOrder = 5 }, {
			Reopen = e("TextButton", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 20, 1, -20),
				Size = UDim2.fromOffset(170, 56),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Text = "BOUTIQUE",
				TextColor3 = Color3.new(0, 0, 0),
				FontFace = Theme.fontBlack,
				TextSize = 18,
				[LuauUI.Event.Activated] = function()
					setOpen(true)
				end,
			}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.ink(), 90), Studs = e(Studs, { tile = 32, transparency = 0.85, radius = 28 }) }),
		})
	end

	-- items of the current category
	local list = {}
	if category == "Vedettes" then
		for _, id in FEATURED do
			table.insert(list, byId[id])
		end
	else
		for _, it in ITEMS do
			if it.cat == category then
				table.insert(list, it)
			end
		end
	end

	local item = byId[selectedId] or list[1]

	local tabs = {
		List = e("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, c in CATEGORIES do
		local count = 0
		for _, it in ITEMS do
			if c.id == "Vedettes" or it.cat == c.id then
				count += 1
			end
		end
		if c.id == "Vedettes" then
			count = #FEATURED
		end
		tabs[c.id] = e(CategoryTab, {
			label = c.id,
			icon = c.icon,
			count = count,
			order = i,
			active = c.id == category,
			onSelect = function()
				setCategory(c.id)
				setNotice(nil)
			end,
		})
	end

	local cards = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.new(0.5, -7, 0.5, -7),
			CellPadding = UDim2.fromOffset(14, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, it in list do
		cards[it.id] = e(ItemCard, {
			item = it,
			order = i,
			selected = it.id == item.id,
			owned = owned[it.id] == true,
			onSelect = function()
				setSelectedId(it.id)
				setNotice(nil)
			end,
		})
	end

	local function onBuy()
		local price = priceOf(item)
		if equipped[item.id] then
			return
		end
		if owned[item.id] then
			local nextEquipped = {}
			for id in equipped do
				if byId[id].cat ~= item.cat then
					nextEquipped[id] = true
				end
			end
			nextEquipped[item.id] = true
			setEquipped(nextEquipped)
			setNotice(item.name .. " équipé")
			return
		end
		if studs < price then
			setNotice("Pas assez de studs pour " .. item.name)
			warn("Achat refusé :", item.name, "coûte", price, "— solde", studs)
			return
		end
		setStuds(studs - price)
		local nextOwned = table.clone(owned)
		nextOwned[item.id] = true
		setOwned(nextOwned)
		setNotice(item.name .. " acheté !")
		print("Acheté :", item.name, "pour", price, "studs — reste", studs - price)
	end

	return e("ScreenGui", { IgnoreGuiInset = true, DisplayOrder = 5 }, {
		Backdrop = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
		}, {
			Studs = e(Studs, { tile = 90, transparency = 0.965 }),
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(1220, 720),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			Corner = corner(UDim.new(0, 34)),
			Gradient = grad(Theme.coal(), 125),
			Stroke = e("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 3, Transparency = 0.55 }),
			Studs = e(Studs, { tile = 70, transparency = 0.955, radius = 34 }),

			-- header
			Title = Label({
				pos = UDim2.fromOffset(30, 24),
				size = UDim2.fromOffset(420, 50),
				text = "BOUTIQUE",
				textSize = 46,
				font = Theme.fontBlack,
				gradient = Theme.ink(),
			}),
			Subtitle = Label({
				pos = UDim2.fromOffset(32, 74),
				size = UDim2.fromOffset(420, 18),
				text = "Dépense tes studs, équipe-toi, domine.",
				textSize = 14,
				font = Theme.fontMedium,
				color = Color3.fromRGB(150, 150, 150),
			}),
			Wallet = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -96, 0, 30),
				Size = UDim2.fromOffset(250, 56),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
			}, {
				Corner = corner(UDim.new(1, 0)),
				Gradient = grad(Theme.night(), 90),
				Stroke = stroke(2, 0.6),
				Icon = e(StudIcon, { size = 40, anchor = Vector2.new(0, 0.5), pos = UDim2.new(0, 8, 0.5, 0) }),
				Amount = Label({
					pos = UDim2.fromOffset(58, 0),
					size = UDim2.new(1, -110, 1, 0),
					text = fmt(studs),
					textSize = 24,
					font = Theme.fontBlack,
					gradient = Theme.ink(),
				}),
				Add = e("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -8, 0.5, 0),
					Size = UDim2.fromOffset(40, 40),
					BackgroundColor3 = Color3.new(1, 1, 1),
					BorderSizePixel = 0,
					Text = "+",
					TextColor3 = Color3.new(0, 0, 0),
					FontFace = Theme.fontBlack,
					TextSize = 26,
					[LuauUI.Event.Activated] = function()
						setStuds(studs + 1000)
						setNotice("+1 000 studs (test)")
					end,
				}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.ink(), 90) }),
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -26, 0, 30),
				Size = UDim2.fromOffset(56, 56),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Text = "✕",
				TextColor3 = Color3.new(0, 0, 0),
				FontFace = Theme.fontBlack,
				TextSize = 24,
				[LuauUI.Event.Activated] = function()
					setOpen(false)
				end,
			}, { Corner = corner(UDim.new(1, 0)), Gradient = grad(Theme.ink(), 90), Stroke = stroke(2, 0.5) }),

			-- left: categories
			Tabs = e("Frame", {
				Position = UDim2.fromOffset(24, 112),
				Size = UDim2.new(0, 200, 1, -136),
				BackgroundTransparency = 1,
			}, tabs),

			-- middle: deal + grid
			Content = e("Frame", {
				Position = UDim2.fromOffset(242, 112),
				Size = UDim2.new(1, -242 - 372, 1, -136),
				BackgroundTransparency = 1,
			}, {
				Deal = e(DealBanner, {
					onSelect = function()
						setSelectedId(DEAL.id)
						setNotice(nil)
					end,
				}),
				Cards = e("Frame", {
					Position = UDim2.fromOffset(0, 166),
					Size = UDim2.new(1, 0, 1, -166),
					BackgroundTransparency = 1,
				}, cards),
			}),

			-- right: details
			Detail = e(Detail, {
				item = item,
				studs = studs,
				owned = owned[item.id] == true,
				equipped = equipped[item.id] == true,
				onBuy = onBuy,
			}),

			-- notice
			Notice = notice and e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(0, 44),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Text = notice,
				TextColor3 = Color3.new(0, 0, 0),
				FontFace = Theme.fontBlack,
				TextSize = 16,
				ZIndex = 5,
			}, {
				Corner = corner(UDim.new(1, 0)),
				Gradient = grad(Theme.ink(), 90),
				Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 22) }),
				Stroke = e("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 3, Transparency = 0.4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			}) or nil,
		}),
	})
end
