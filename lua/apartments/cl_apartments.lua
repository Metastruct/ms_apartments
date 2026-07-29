require("hookgroup")
module("ms", package.seeall)
local tag = "ms_apartments"

local Apartments = Apartments or {}
_M.Apartments = Apartments

local rooms, entrances
if Apartments.GetRooms then
	rooms = table.Copy(Apartments.GetRooms())
	entrances = table.Copy(Apartments.GetEntrances())
else
	rooms = {}
	entrances = {}
end

local PASSAGE_GUESTS = 1
local PASSAGE_FRIENDS = 2
local PASSAGE_ALL = 3

local TRANSFER_TRANSFER = 1
local TRANSFER_WILL = 2

local SV_NET_UPDATE_BOTH = 1
local SV_NET_UPDATE_ROOMS = 2
local SV_NET_UPDATE_ENTRANCES = 3

local CL_NET_RENT = 4
local CL_NET_INVITE = 5
local CL_NET_PASSAGE = 6
local CL_NET_TRANSFER = 7

local hooks
local willed_to
local is_client_renting
local apartment_ui_last_open = 0

if Apartments.hkgrp then
	hooks = Apartments.hkgrp
else
	hooks = hookgroup.NewObj(tag)
	Apartments.hkgrp = hooks
end

if Apartments.GetMyRoom then
	is_client_renting = Apartments.GetMyRoom()
else
	is_client_renting = false
end

local function request_rent_from_server(room_number, state)
	net.Start(tag)
	net.WriteUInt(CL_NET_RENT, 32)
	net.WriteUInt(room_number, 32)
	net.WriteUInt(state, 32)
	net.SendToServer()
end

local function request_invite_from_server(room_number, state, guest_uid)
	net.Start(tag)
	net.WriteUInt(CL_NET_INVITE, 32)
	net.WriteUInt(room_number, 32)
	net.WriteUInt(state, 32)
	net.WriteUInt(guest_uid, 32)
	net.SendToServer()
end

local function request_passage_from_server(room_number, state)
	net.Start(tag)
	net.WriteUInt(CL_NET_PASSAGE, 32)
	net.WriteUInt(room_number, 32)
	net.WriteUInt(state, 32)
	net.SendToServer()
end

local function request_transfer_from_server(room_number, state, new_tenant)
	net.Start(tag)
	net.WriteUInt(CL_NET_TRANSFER, 32)
	net.WriteUInt(room_number, 32)
	net.WriteUInt(state, 32)
	net.WritePlayer(new_tenant)
	net.SendToServer()
end

local function apartment_ui(room_number)
	local room = rooms[room_number]
	local tenant = player.GetBySteamID64(room.tenant)

	local root_color = Color(110, 110, 110, 255)
	local btn_hover_color = Color(240, 240, 240, 255)

	local root = vgui.Create("DFrame")
	root:SetSize(250, 250)
	root:SetSizable(false)
	root:SetTitle(room.name)
	root:Center()
	root:MakePopup()

	function root:Paint(w, h)
		draw.RoundedBox(10, 0, 0, w, h, root_color)
	end

	local property_sheet = root:Add("DPropertySheet")
	property_sheet:Dock(FILL)

	function property_sheet:Paint(w, h)
		surface.SetDrawColor(color_transparent)
		surface.DrawRect(0, 0, w, h)
	end

	local rent_panel = property_sheet:Add("DPanel")
	property_sheet:AddSheet("Renting", rent_panel, "icon16/door_open.png")

	function rent_panel:Paint(w, h) end

	local rent_lb = rent_panel:Add("DLabel")
	rent_lb:SetText("You can only own one room at a time\nRooms expire when abandoned or 5 minutes\nafter you leave.")
	rent_lb:SetTextColor(color_white)
	rent_lb:SizeToContentsY()
	rent_lb:Dock(TOP)
	rent_lb:DockMargin(2, 7, 0, 0)

	local rent_btn = rent_panel:Add("DButton")

	if not room.tenant or tenant == LocalPlayer() then
		rent_btn:SetEnabled(true)
	else
		rent_btn:SetEnabled(false)
	end

	rent_btn:SetText(tenant == LocalPlayer() and "Abandon Room" or "Rent Room")
	rent_btn:SetHeight(50)
	rent_btn:Dock(BOTTOM)

	function rent_btn:Paint(w, h)
		surface.SetDrawColor((self:IsEnabled() and self:IsHovered()) and btn_hover_color or color_white)
		surface.DrawRect(0, 0, w, h)
	end

	function rent_btn:DoClick()
		request_rent_from_server(room_number, is_client_renting and 0 or 1)
		root:Close()
	end

	if not is_client_renting or is_client_renting ~= room_number then return end

	local invite_panel = property_sheet:Add("DPanel")
	property_sheet:AddSheet("Invitations", invite_panel, "icon16/group.png")
	property_sheet:SetActiveTab(property_sheet:GetItems()[2].Tab)

	function invite_panel:Paint(w, h) end

	local invite_lb = invite_panel:Add("DLabel")
	invite_lb:SetText("Invite players, also grants building privileges")
	invite_lb:SetTextColor(color_white)
	invite_lb:Dock(TOP)
	invite_lb:DockMargin(2, 0, 0, 0)

	local invite_list = invite_panel:Add("DComboBox")
	invite_list:SetValue("Choose a player")
	invite_list:Dock(TOP)
	invite_list:DockMargin(0, 7, 0, 0)

	for _, ply in pairs(player.GetAll()) do
		if ply ~= LocalPlayer() then
			local nick = ply:Nick()
			invite_list:AddChoice(nick, ply, false, room.guests[ply:UserID()] and "icon16/award_star_gold_1.png")
		end
	end

	local invite_btn = invite_panel:Add("DButton")
	invite_btn:SetEnabled(false)
	invite_btn:SetText("Invite Player")
	invite_btn:Dock(TOP)
	invite_btn:DockMargin(0, 7, 0, 0)

	function invite_btn:Paint(w, h)
		surface.SetDrawColor((self:IsEnabled() and self:IsHovered()) and btn_hover_color or color_white)
		surface.DrawRect(0, 0, w, h)
	end

	function invite_btn:DoClick()
		local _, ply = invite_list:GetSelected()
		if not ply then return end

		local ply_uid = ply:UserID()
		request_invite_from_server(room_number, room.guests[ply_uid] and 0 or 1, ply_uid)
		root:Close()
	end

	function invite_list:OnSelect()
		local _, ply = self:GetSelected()
		if not ply then return end

		invite_btn:SetText(room.guests[ply:UserID()] and "Kick" or "Invite")
		invite_btn:SetEnabled(true)
	end

	local passage_lb = invite_panel:Add("DLabel")
	passage_lb:SetText("Control passage to your apartment")
	passage_lb:SetTextColor(color_white)
	passage_lb:Dock(TOP)
	passage_lb:DockMargin(2, 14, 0, 0)

	local passage = invite_panel:Add("DComboBox")
	local passage_ref = {"Guests only", "Guests & Friends", "Everyone"}
	passage:SetValue(passage_ref[room.passage])
	passage:AddChoice("Guests only", PASSAGE_GUESTS)
	passage:AddChoice("Guests & Friends", PASSAGE_FRIENDS)
	passage:AddChoice("Everyone", PASSAGE_ALL)
	passage:Dock(TOP)
	passage:DockMargin(0, 7, 0, 0)

	local passage_btn = invite_panel:Add("DButton")
	passage_btn:SetEnabled(false)
	passage_btn:SetText("Confirm")
	passage_btn:Dock(TOP)
	passage_btn:DockMargin(0, 7, 0, 0)

	function passage_btn:Paint(w, h)
		surface.SetDrawColor(self:IsHovered() and btn_hover_color or color_white)
		surface.DrawRect(0, 0, w, h)
	end

	function passage_btn:DoClick()
		local _, new_state = passage:GetSelected()
		request_passage_from_server(room_number, new_state)
		root:Close()
	end

	function passage:OnSelect()
		passage_btn:SetEnabled(true)
	end

	local transfer_panel = property_sheet:Add("DPanel")
	property_sheet:AddSheet("Transfer", transfer_panel, "icon16/house_go.png")

	function transfer_panel:Paint(w, h) end

	local transfer_lb = transfer_panel:Add("DLabel")
	transfer_lb:SetText("Transfer/will your apartment to:\n" ..
						"(willing your room transfers it after you\nleave and your grace period expires)")
	transfer_lb:SizeToContentsY()
	transfer_lb:SetTextColor(color_white)
	transfer_lb:Dock(TOP)
	transfer_lb:DockMargin(0, 7, 0, 0)

	local transfer_list = transfer_panel:Add("DComboBox")
	transfer_list:SetValue("Choose a player")
	transfer_list:Dock(TOP)
	transfer_list:DockMargin(0, 7, 0, 0)

	for _, ply in pairs(player.GetAll()) do
		if ply ~= LocalPlayer() then
			local nick = ply:Nick()
			transfer_list:AddChoice(nick, ply, false, willed_to == ply and "icon16/award_star_gold_1.png")
		end
	end

	local will_btn = transfer_panel:Add("DButton")
	will_btn:SetEnabled(false)
	will_btn:SetText("Will room")
	will_btn:Dock(BOTTOM)
	will_btn:DockMargin(0, 7, 0, 0)

	function will_btn:DoClick()
		local _, ply = transfer_list:GetSelected()
		if not ply then return end

		willed_to = willed_to ~= ply and ply or nil
		request_transfer_from_server(room_number, TRANSFER_WILL, ply)
		root:Close()
	end

	local transfer_btn = transfer_panel:Add("DButton")
	transfer_btn:SetEnabled(false)
	transfer_btn:SetText("Transfer room")
	transfer_btn:Dock(BOTTOM)
	transfer_btn:DockMargin(0, 7, 0, 0)

	function transfer_btn:DoClick()
		local _, ply = transfer_list:GetSelected()
		if not ply then return end

		request_transfer_from_server(room_number, TRANSFER_TRANSFER, ply)
		root:Close()
	end

	function transfer_list:OnSelect()
		will_btn:SetEnabled(true)
		transfer_btn:SetEnabled(true)

		local _, ply = self:GetSelected()
		will_btn:SetText(willed_to == ply and "Undo will" or "Will room")
	end
end

function Apartments.GetMyRoom()
	return is_client_renting
end

function Apartments.GetRooms()
	return rooms
end

function Apartments.GetEntrances()
	return entrances
end

net.Receive(tag, function()
	local id = net.ReadUInt(32)

	if id == SV_NET_UPDATE_BOTH or id == SV_NET_UPDATE_ROOMS then
		local payload_size = net.ReadUInt(32)
		rooms = util.JSONToTable(util.Decompress(net.ReadData(payload_size)))

		is_client_renting = false
		local lp = LocalPlayer()
		local my_id64 = lp and lp.SteamID64 and lp:SteamID64()
		if my_id64 then
			for room_number, room in pairs(rooms) do
				if room.tenant == my_id64 then
					is_client_renting = room_number
				end
			end
		end
	end

	if id == SV_NET_UPDATE_BOTH or id == SV_NET_UPDATE_ENTRANCES then
		local payload_size = net.ReadUInt(32)
		entrances = util.JSONToTable(util.Decompress(net.ReadData(payload_size)))
	end
end)

hooks:Add("KeyPress", tag, function(ply, key)
	if key ~= IN_RELOAD then return end

	local trace = ply:GetEyeTrace()
	if trace.StartPos:DistToSqr(trace.HitPos) > 10000 then return end

	local room_number = entrances[trace.Entity:EntIndex()]
	if not room_number then return end

	if apartment_ui_last_open + 1 < CurTime() then
		apartment_ui(room_number)
		apartment_ui_last_open = CurTime()
	end
end)

hook.Add("lua_trigger", tag, function(place, inside)
	if place ~= "apartments" then return end

	if inside then
		hooks:Activate()
	else
		hooks:Deactivate()
	end
end)
