module("ms", package.seeall)

-- coloring ui is still it's own thing somewhere else
-- should probably be move here?

local DefaultColors = {}
local Materials = {
	["livingroom"]        = Material("METASTRUCT_4/APARTMENT/APARTMENT_PLASTER01A_LIVINGROOM"),
	["livingroom_carpet"] = Material("METASTRUCT_4/LOBBY_CARPET01B"),

	["kitchen"]  = Material("METASTRUCT_4/APARTMENT/APARTMENT_PLASTER01A_KITCHEN"),
	["washroom"] = Material("METASTRUCT_4/APARTMENT/APARTMENT_PLASTER01A_WASHROOM"),

	["bedroom"]        = Material("METASTRUCT_4/APARTMENT/APARTMENT_PLASTER01A_BEDROOM"),
	["bedroom_carpet"] = Material("APARTMENT/CARPET01"),

	["ceiling"] = Material("AJACKS/BEN_WHITECEILING")
}

for name, mat in next, Materials do
	DefaultColors[name] = mat:GetVector("$color")
end

-- sometimes colors are tables, Color:ToVector may not work
local function toVec(col)
	return Vector(col.r / 255, col.g / 255, col.b / 255)
end

function Apartments.SetSurfaceColor(name, color)
	name = name:lower()
	local mat = Materials[name]
	mat:SetVector("$color", toVec(color))
	mat:Recompute()
end

function Apartments.ResetSurfaceColor(name)
	name = name:lower()
	local mat = Materials[name]
	mat:SetVector("$color", DefaultColors[name])
	mat:Recompute()
end

function Apartments.GetSurfaceColor(name)
	name = name:lower()
	return Materials[name]:GetVector("$color"):ToColor()
end

-- These are supposed to be the defaults.
-- Due to the a material change during a few versions of the map,
-- These are super dark, so we manually fix the color
if Materials["livingroom"]:GetVector("$color").x < 0.1 then
	hook.Add("InitPostEntity", "AptColorFix", function()
		DefaultColors["livingroom"] = Vector(0.42, 0.42, 0.54)
		DefaultColors["bedroom"]    = Vector(0.66, 0.50, 0.39)
		DefaultColors["washroom"]   = Vector(1, 1, 1)

		Apartments.ResetSurfaceColor("livingroom")
		Apartments.ResetSurfaceColor("bedroom")
		Apartments.ResetSurfaceColor("washroom")

		hook.Remove("InitPostEntity", "AptColorFix")
	end)
end