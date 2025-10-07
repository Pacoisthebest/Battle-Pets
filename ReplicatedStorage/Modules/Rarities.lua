-- ReplicatedStorage/Modules/Rarities.lua
-- Simple styling utilities by rarity (colors + UIGradient + UIStroke)

local Rarities = {}

-- Configure your rarities here (hex or Color3).
-- gradient = { startHex, endHex, ... }  (2+ stops supported)
local STYLES = {
	Default   = { color = "#C9CDD1", gradient = { "#FFFFFF", "#C9CDD1" }, stroke = "#8E949A" },

	Common    = { color = "#dadada", gradient = { "#F5F7FA", "#BAC2CE" }, stroke = "#7C8594", layout = "1" , eggImage = ""},
	Uncommon  = { color = "#73ff63", gradient = { "#B9EBAF", "#34C759" }, stroke = "#2E7D32", layout = "2" , eggImage = "" },
	Rare      = { color = "#2fe3ff", gradient = { "#50ECFF", "#206FFF" }, stroke = "#0d306b", layout = "3" , eggImage = "" },
	Epic      = { color = "#B24DFF", gradient = { "#fe4ded", "#c61aff" }, stroke = "#2d063a", layout = "4" , eggImage = "" },
	Legendary = { color = "#FFC83D", gradient = { "#FFF2B0", "#FFB300" }, stroke = "#C78A00", layout = "5" , eggImage = "" },
	Mythic    = { color = "#FF4D6D", gradient = { "#FFB3C1", "#FF2E63" }, stroke = "#B00020", layout = "6" , eggImage = "" },
	Divine    = { color = "#00E5FF", gradient = { "#A0F4FF", "#00B8D4" }, stroke = "#007EA1", layout = "7" , eggImage = "" },
}

-- ===== helpers =====

local function toColor3(v)
	if typeof(v) == "Color3" then return v end
	local hex = tostring(v or ""):gsub("#","")
	if #hex == 3 then hex = hex:sub(1,1):rep(2)..hex:sub(2,2):rep(2)..hex:sub(3,3):rep(2) end
	local r = tonumber(hex:sub(1,2),16) or 0
	local g = tonumber(hex:sub(3,4),16) or 0
	local b = tonumber(hex:sub(5,6),16) or 0
	return Color3.fromRGB(r,g,b)
end

local function toSequence(arr, fallback)
	if not arr or #arr == 0 then
		local c = toColor3(fallback or "#FFFFFF")
		return ColorSequence.new(c)
	end
	local keys = {}
	for i,hex in ipairs(arr) do
		local alpha = (#arr == 1) and 0 or (i-1)/(#arr-1)
		table.insert(keys, ColorSequenceKeypoint.new(alpha, toColor3(hex)))
	end
	return ColorSequence.new(keys)
end

local function ensureGradient(gui)
	local g = gui:FindFirstChildOfClass("UIGradient")
	if not g then
		g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Parent = gui
		-- Tip: set g.Transparency if you want fading ends
	end
	return g
end

local function ensureStroke(gui)
	local s = gui:FindFirstChildOfClass("UIStroke")
	if not s then
		s = Instance.new("UIStroke")
		s.Thickness = 1
		s.Transparency = 0.2
		s.Parent = gui
	end
	return s
end

-- compile styles (case-insensitive keys)
local COMPILED = {}
-- inside the COMPILED build loop:
for name, s in pairs(STYLES) do
	COMPILED[string.lower(name)] = {
		name     = name,
		color    = toColor3(s.color),
		gradient = toSequence(s.gradient, s.color),
		stroke   = toColor3(s.stroke or s.color),
		rank     = tonumber(s.layout) or 0, -- <- ADD
	}
end

function Rarities.RankOf(rarity) -- <- ADD
	return (Rarities.Get(rarity).rank) or 0
end

-- ===== public API =====
function Rarities.Get(rarity)
	local key = rarity and string.lower(tostring(rarity)) or "default"
	return COMPILED[key] or COMPILED.default
end

function Rarities.ColorOf(rarity)
	return Rarities.Get(rarity).color
end

function Rarities.GradientOf(rarity)
	return Rarities.Get(rarity).gradient
end

function Rarities.StrokeOf(rarity)
	return Rarities.Get(rarity).stroke
end

-- Apply gradient/stroke to a TextLabel (for gradient text)
function Rarities.ApplyToText(textLabel, rarity, opts)
	if not (textLabel and textLabel:IsA("TextLabel")) then return end
	local style = Rarities.Get(rarity)
	-- Text must be visible for UIGradient to tint it; white keeps gradient true
	textLabel.TextColor3 = Color3.new(1,1,1)
	textLabel.RichText = textLabel.RichText -- preserve whatever you had

	local g = ensureGradient(textLabel)
	g.Color = style.gradient
	if not (opts and opts.NoStroke) then
		local s = ensureStroke(textLabel)
		s.Color = style.stroke
	end
end

-- Apply gradient/stroke to any GuiObject background (buttons, frames)
function Rarities.ApplyToGui(guiObject, rarity, opts)
	if not (guiObject and guiObject:IsA("GuiObject")) then return end
	local style = Rarities.Get(rarity)
	guiObject.BackgroundColor3 = style.color
	local g = ensureGradient(guiObject)
	g.Color = style.gradient
	if not (opts and opts.NoStroke) then
		local s = ensureStroke(guiObject)
		s.Color = style.stroke
	end
end

-- Apply tint/gradient to an ImageLabel or ImageButton
function Rarities.ApplyToImage(imageObject, rarity, opts)
	if not (imageObject and (imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton"))) then
		return
	end
	local style = Rarities.Get(rarity)

	-- Flat tint
	imageObject.ImageColor3 = style.color
	
	if not (opts and opts.NoGradient) then
		local g = imageObject:FindFirstChildOfClass("UIGradient")
		if not g then
			g = Instance.new("UIGradient")
			g.Rotation = 0
			g.Parent = imageObject
		end
		g.Color = style.gradient
	end

end


return Rarities
