module("ms", package.seeall)
local tag = "ms_apartments"

local null = NULL

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
local color_black = Color(0, 0, 0, 255)
local color_red = Color(255, 0, 0, 255)
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

-- What has changed?
local NET_RENT = 0
local NET_INVITE = 1
local NET_INFO = 2

-- The change itself
local NET_KICK = 0
local NET_ADMIT = 1
local NET_SET_PUBLIC = 2
local NET_INVITE_FRIENDS = 3

local function network_rent_change(room_n, change)
	net.Start(tag)
	net.WriteInt(NET_RENT, 3)
	net.WriteInt(room_n, 5)
	net.WriteInt(change, 3)
	net.SendToServer()
end

local function network_invite_change(room_n, change, target)
	net.Start(tag)
	net.WriteInt(NET_INVITE, 3)
	net.WriteInt(room_n, 5)
	net.WriteInt(change, 3)

	if change ~= NET_SET_PUBLIC and change ~= NET_INVITE_FRIENDS then net.WriteEntity(target) end

	net.SendToServer()
end

local function receive_rent_change(ply, room_n, change)
	if change == NET_ADMIT then
		Apartments.List[room_n].tenant = ply
		Apartments.Tenants[ply] = room_n

		return
	end

	if change == NET_KICK then
		Apartments.Tenants[ply] = nil

		local room = Apartments.List[room_n]
		room.tenant = nil
		room.public = false
		room.invitees = {}
	end
end

local function receive_info(networked_entrances, networked_tenants)
	networked_entrances = util.Decompress(networked_entrances)
	networked_tenants = util.Decompress(networked_tenants)

	networked_entrances = util.JSONToTable(networked_entrances)
	networked_tenants = util.JSONToTable(networked_tenants)

	local entrances = {}
	for entrance_index, room_n in pairs(networked_entrances) do
		entrances[Entity(entrance_index)] = room_n
	end

	local tenants = {}
	for tenant_index, room_n in pairs(networked_tenants) do
		tenants[tenant_index] = nil
		tenants[Entity(tenant_index)] = room_n
	end

	Apartments.Entrances = entrances
	for tenant, room_n in pairs(tenants) do
		receive_rent_change(tenant, room_n, NET_ADMIT)
	end
end

net.Receive(tag, function()
	local net_type = net.ReadInt(3)

	if net_type == NET_INFO then
		local entrances_size = net.ReadUInt(16)
		local entrances_networkable = net.ReadData(entrances_size)
		local tenants_size = net.ReadUInt(16)
		local tenants_networkable = net.ReadData(tenants_size)

		receive_info(entrances_networkable, tenants_networkable)
		return
	end

	local room_n = net.ReadInt(5)
	local change = net.ReadInt(3)

	local ply = net.ReadEntity()

	receive_rent_change(ply, room_n, change)
end)

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

local function is_invited(ply, room_n)
	return Apartments.List[room_n].invitees[ply:SteamID64()]
end

local frame_color = Color(55, 50, 55, 240)
local btn_hover_color = Color(200, 200, 200, 255)

local btn_paint = function(self, w, h)
	surface.SetDrawColor((self:IsHovered() and self:IsEnabled()) and btn_hover_color or not self:IsEnabled() and btn_hover_color or color_white)
	surface.DrawRect(0, 0, w, h)
end

local function invite_ui(room_n, frame)
	local invite_list, invite_btn, friends_btn

	invite_list = frame:Add("DComboBox")
	invite_list:SetValue("Choose a player")
	invite_list:Dock(TOP)
	invite_list:DockMargin(0, 7, 0, 0)
	invite_list.Paint = btn_paint
	function invite_list:OnSelect()
		local _, ply = self:GetSelected()
		if not ply then return end

		local str = is_invited(ply, room_n) and "Kick" or "Invite"
		invite_btn:SetText(str)
		invite_btn:SetEnabled(true)
	end

	for _, ply in ipairs(player.GetAll()) do
		if ply == LocalPlayer() then continue end

		local nick = ply:Nick()
		invite_list:AddChoice(nick, ply, false, is_invited(ply, room_n) and "icon16/award_star_gold_1.png")
	end

	invite_btn = frame:Add("DButton")
	invite_btn:SetText("")
	invite_btn:SetEnabled(false)
	invite_btn:Dock(TOP)
	invite_btn:DockMargin(0, 7, 0, 0)
	invite_btn.Paint = btn_paint
	function invite_btn:DoClick()
		local _, ply = invite_list:GetSelected()

		network_invite_change(room_n, is_invited(ply, room_n) and NET_KICK or NET_ADMIT, ply)
		Apartments.List[room_n].invitees[ply:SteamID64()] = not is_invited(ply, room_n)

		frame:Remove()
	end

	friends_btn = frame:Add("DButton")
	friends_btn:SetText(Apartments.List[room_n].friendly and "Kick out all friends" or "My friends can enter")
	friends_btn:Dock(TOP)
	friends_btn:DockMargin(0, 7, 0, 0)
	friends_btn.Paint = btn_paint
	function friends_btn:DoClick()
		frame:Remove()

		network_invite_change(room_n, NET_INVITE_FRIENDS)
		Apartments.List[room_n].friendly = not Apartments.List[room_n].friendly
	end
end

local function rent_ui(room_n)
	local room = Apartments.List[room_n]

	local tenant = room.tenant
	local am_renting = Apartments.Tenants[player.GetByID(LocalPlayer():EntIndex())]
	local rented_by_me = tenant == LocalPlayer()

	local frame_w, frame_h = 200, 150
	local frame, rent_btn, invite_btn, public_btn, color_btn

	local rent_btn_txt = ""
	local rent_btn_enabled = not rented_by_me and false or rented_by_me or (not am_renting and not tenant)
	local rent_btn_color = rent_btn_enabled and color_black or color_red
	rent_btn_txt = rent_btn_txt .. (rented_by_me and "Abandon apartment" or "")
	rent_btn_txt = rent_btn_txt .. (not am_renting and not tenant and "Rent me!" or "")

	local invite_btn_txt = ""
	local invite_btn_enabled = rented_by_me
	local invite_btn_color = invite_btn_enabled and color_black or color_red
	invite_btn_txt = invite_btn_txt .. (rented_by_me and "Invite" or "")

	local public_btn_txt = ""
	public_btn_txt = public_btn_txt .. (rented_by_me and (room.public and "Set private" or "Set public") or "")

	local unav = "UNAVAILABLE"
	rent_btn_txt = rent_btn_enabled and rent_btn_txt or rent_btn_txt .. unav
	invite_btn_txt = invite_btn_enabled and invite_btn_txt or invite_btn_txt .. unav
	public_btn_txt = invite_btn_enabled and public_btn_txt or public_btn_txt .. unav

	frame = vgui.Create("DFrame")
	frame:SetTitle(("Apt. Room %02d"):format(room_n))
	frame:SetSize(frame_w, frame_h)
	frame:SetDraggable(false)
	frame:ShowCloseButton(true)
	frame:Center()

	function frame:Paint(w, h)
		surface.SetDrawColor(frame_color)
		surface.DrawRect(0, 0, w, h)

		surface.SetDrawColor(color_white)
		self:DrawOutlinedRect()
	end

	rent_btn = frame:Add("DButton")
	rent_btn:SetTextColor(rent_btn_color)
	rent_btn:SetText(rent_btn_txt)
	rent_btn:SetEnabled(rent_btn_enabled)
	rent_btn:Dock(TOP)
	rent_btn:DockMargin(0, 7, 0, 0)
	rent_btn.Paint = btn_paint
	function rent_btn:DoClick()
		frame:Remove()

		if rented_by_me then
			Derma_Query("Abandoning apartment, are you sure?", "Confirmation", "Yes", function()
				network_rent_change(room_n, NET_KICK)
			end, "Nevermind!")

			return
		end

		network_rent_change(room_n, NET_ADMIT)
	end

	invite_btn = frame:Add("DButton")
	invite_btn:SetTextColor(invite_btn_color)
	invite_btn:SetText(invite_btn_txt)
	invite_btn:SetEnabled(invite_btn_enabled)
	invite_btn:Dock(TOP)
	invite_btn:DockMargin(0, 7, 0, 0)
	invite_btn.Paint = btn_paint
	function invite_btn:DoClick()
		rent_btn:Remove()
		public_btn:Remove()
		color_btn:Remove()
		self:Remove()

		invite_ui(room_n, frame)

		frame:SetTall(120)
	end

	public_btn = frame:Add("DButton")
	public_btn:SetTextColor(invite_btn_color)
	public_btn:SetText(public_btn_txt)
	public_btn:SetEnabled(invite_btn_enabled)
	public_btn:Dock(TOP)
	public_btn:DockMargin(0, 7, 0, 0)
	public_btn.Paint = btn_paint
	function public_btn:DoClick()
		frame:Remove()

		room.public = not room.public
		network_invite_change(room_n, NET_SET_PUBLIC)
	end

	color_btn = frame:Add("DButton")
	color_btn:SetText("Coloring (client only)")
	color_btn:Dock(TOP)
	color_btn:DockMargin(0, 7, 0, 0)
	color_btn.Paint = btn_paint
	function color_btn:DoClick()
		frame:Remove()
		RunConsoleCommand("ms_apartments_color_gui")
	end

	frame:MakePopup()
end

local function draw_door_sign(room_n, tenant)
	local sign_x, sign_y = 80, -370
	local sign_w, sign_h = 300, 100
	local room_n_x, room_n_y = 372, -355
	local owner_x, owner_y = 230, -320

	draw.RoundedBox(15, sign_x, sign_y, sign_w, sign_h, color_dark)
	draw.SimpleText("Apartment " .. room_n, "apartments_sub", room_n_x, room_n_y, color_purple, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	if not tenant or tenant == null then
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

	draw.SimpleText(tenant:Nick(), "apartments_name", owner_x, owner_y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function PostDrawOpaqueRenderables_Doors()
	local ep = LocalPlayer():EyePos()

	for entrance, room_n in pairs(Apartments.Entrances) do
		if entrance == null then Apartments.Entrances[entrance] = nil continue end
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

require("hookgroup")

local hooks = hookgroup.NewObj(tag)
Apartments.hkgrp = hooks

local MAX_RANGE = 10000
local last_press = 0
hooks:Add("KeyPress", function(ply, key)
	if key ~= IN_RELOAD then return end

	local trace = ply:GetEyeTrace()
	local room_n = Apartments.Entrances[trace.Entity]
	if not room_n then return end

	if trace.StartPos:DistToSqr(trace.HitPos) > MAX_RANGE then return end
	if last_press + 1 > CurTime() then return end
	last_press = CurTime()

	rent_ui(room_n)
end)

hooks:Add("PostDrawOpaqueRenderables", function()
	PostDrawOpaqueRenderables_Doors()
end)

hook.Add("lua_trigger", tag, function(place, inside)
	if place ~= "apartments" then return end

	if inside then
		hooks:Activate()
	else
		hooks:Deactivate()
	end
end)