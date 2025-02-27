module("ms", package.seeall)

surface.CreateFont("apartments_name", {
	font = "Segoe UI Semibold",
	extended = false,
	size = 50,
	weight = 500,
})

surface.CreateFont("apartments_sub", {
	font = "Segoe UI Semibold",
	extended = false,
	size = 24,
	weight = 500,
})

local color_white = Color(255, 255, 255, 255)
local color_purple = Color(130, 65, 130, 255)
local color_dark = Color(32, 32, 32, 200)

local logo = {}
for i = 1, 3 do
	local spacing = 30 * i
	local static = 90
	local offset = -370

	i = {
		{
			x = -25 + static + spacing,
			y = 0 + offset
		},
		{
			x = -5 + static + spacing,
			y = 0 + offset
		},
		{
			x = 35 + static + spacing,
			y = 100 + offset
		},
		{
			x = 15 + static + spacing,
			y = 100 + offset
		}
	}

	table.insert(logo, i)
end

local function draw_door_sign(room_n, tenant_sid64)
	local sign_x, sign_y = 80, -370
	local sign_w, sign_h = 300, 100
	local room_n_x, room_n_y = 372, -355
	local owner_x, owner_y = 230, -320

	draw.RoundedBox(15, sign_x, sign_y, sign_w, sign_h, color_dark)
	draw.SimpleText("Apartment " .. room_n, "apartments_sub", room_n_x, room_n_y, color_purple, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	if not tenant_sid64 then
		for i = 1, 3 do
			local r, g, b, a = 70 + 15 * i, 200 + 10 * i, 70 + 20 * i, 150
			surface.SetDrawColor(r, g, b, a)

			draw.NoTexture()
			surface.DrawPoly(logo[i])
		end

		draw.SimpleText("No Owner", "apartments_name", owner_x, owner_y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		return
	end

	for i = 1, 3 do
		local r, g, b, a = 95 + 15 * i, 35 + 10 * i, 90 + 20 * i, 150
		surface.SetDrawColor(r, g, b, a)

		draw.NoTexture()
		surface.DrawPoly(logo[i])
	end

	local tenant_name = get_by_sid64(tenant_sid64)
	tenant_name = tenant_name and tenant_name:Nick() or "DISCONNECTED"

	draw.SimpleText(tenant_name, "apartments_name", owner_x, owner_y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function PostDrawOpaqueRenderables_Doors()
	local ep = LocalPlayer():EyePos()
	local entrances = Apartments.GetEntrances()

	for entrance, room_n in pairs(entrances) do
		if entrance == null then entrances[entrance] = nil continue end
		if ep:DistToSqr(entrance:GetPos()) > 400 ^ 2 then continue end

		local room = Apartments.List[room_n]
		if not room then continue end

		local cpos = entrance:GetPos() + entrance:GetForward() * 2
		local cang = entrance:GetAngles() + Angle(0, 90, 90)
		local cscale = .1

		cam.Start3D2D(cpos, cang, cscale)
		draw_door_sign(room_n, room.tenant)
		cam.End3D2D()
	end
end

Apartments.hkgrp:Add("PostDrawOpaqueRenderables", PostDrawOpaqueRenderables_Doors)