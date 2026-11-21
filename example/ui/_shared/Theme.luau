-- Shared theme: black & white, gradients everywhere.
local Theme = {}

Theme.white = Color3.fromRGB(255, 255, 255)
Theme.black = Color3.fromRGB(0, 0, 0)

Theme.font = Font.fromName("Montserrat", Enum.FontWeight.Bold)
Theme.fontBlack = Font.fromName("Montserrat", Enum.FontWeight.Heavy)
Theme.fontMedium = Font.fromName("Montserrat", Enum.FontWeight.Medium)

-- Stud textures from ui-resources.com (Textures > Stud).
-- In the preview they load from example/assets. In Roblox, upload them and
-- replace these with "rbxassetid://<id>".
Theme.studTexture = "assets/stud_texture.png"
Theme.studIcon = "assets/stud_single.png"

-- Vertical gradients (Rotation 90 = top to bottom)
function Theme.ink()
	return ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150))
end

function Theme.coal()
	return ColorSequence.new(Color3.fromRGB(62, 62, 62), Color3.fromRGB(6, 6, 6))
end

function Theme.steel()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(110, 110, 110)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 30, 30)),
	})
end

function Theme.night()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 44, 44)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(14, 14, 14)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
	})
end

function Theme.chrome()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(170, 170, 170)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(95, 95, 95)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(225, 225, 225)),
	})
end

return Theme
