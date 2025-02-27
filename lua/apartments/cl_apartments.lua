require("hookgroup")
module("ms", package.seeall)
local tag = "ms_apartments"

local Apartments = Apartments or {}
_M.Apartments = Apartments

local rooms = {}
local entrances = {}

local PASSAGE_GUESTS = 1
local PASSAGE_FRIENDS = 2
local PASSAGE_ALL = 3

local SV_NET_UPDATE_BOTH = 1
local SV_NET_UPDATE_ROOMS = 2
local SV_NET_UPDATE_ENTRANCES = 3

local CL_NET_RENT = 4
local CL_NET_INVITE = 5
local CL_NET_PASSAGE = 6

local hooks = hookgroup.NewObj(tag)
Apartments.hkgrp = hooks

local apartment_ui_last_open = 0
local is_client_renting = false

local function request_action_from_server(id, room_number, state, guest_uid)
    net.Start(tag)
    net.WriteUInt(id, 32)
    net.WriteUInt(room_number, 32)
    net.WriteUInt(state, 32)

    if id == CL_NET_INVITE then
        net.WriteUInt(guest_uid, 32)
    end

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
    rent_lb:SetText("You can only own one room at a time\nRooms expire when abandoned or 3 minutes\nafter you leave.")
    rent_lb:SetTextColor(color_white)
    rent_lb:SizeToContentsY()
    rent_lb:Dock(TOP)
    rent_lb:DockMargin(2, 7, 0, 0)

    local rent_btn = rent_panel:Add("DButton")
    if is_client_renting and tenant ~= LocalPlayer() then
        rent_btn:SetEnabled(false)
    else
        rent_btn:SetEnabled(true)
    end
    rent_btn:SetText(tenant == LocalPlayer() and "Abandon Room" or "Rent Room")
    rent_btn:SetHeight(50)
    rent_btn:Dock(BOTTOM)

    function rent_btn:Paint(w, h)
        surface.SetDrawColor((self:IsEnabled() and self:IsHovered()) and btn_hover_color or color_white)
        surface.DrawRect(0, 0, w, h)
    end

    function rent_btn:DoClick()
        request_action_from_server(CL_NET_RENT, room_number, is_client_renting and 0 or 1)
        root:Close()
    end

    if not is_client_renting or is_client_renting ~= room_number then return end

    local invite_panel = property_sheet:Add("DPanel")
    property_sheet:AddSheet("Invitations", invite_panel, "icon16/group.png")

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
        local ply_uid = ply:UserID()
        request_action_from_server(CL_NET_INVITE, room_number, room.guests[ply_uid] and 0 or 1, ply_uid)
        root:Close()
    end

    function invite_list:OnSelect()
        local _, ply = self:GetSelected()
        if not ply then return end

        invite_btn:SetText(room.guests[ply:UserID()] and "Kick" or "Invite")
        invite_btn:SetEnabled(true)
    end

    local who_can_enter_lb = invite_panel:Add("DLabel")
    who_can_enter_lb:SetText("Control passage to your apartment")
    who_can_enter_lb:SetTextColor(color_white)
    who_can_enter_lb:Dock(TOP)
    who_can_enter_lb:DockMargin(2, 14, 0, 0)

    local who_can_enter = invite_panel:Add("DComboBox")
    local wce_ref = {"Guests only", "Guests and Friends", "Everyone"}
    who_can_enter:SetValue(wce_ref[room.passage])
    who_can_enter:AddChoice("Guests only", PASSAGE_GUESTS)
    who_can_enter:AddChoice("Guests and Friends", PASSAGE_FRIENDS)
    who_can_enter:AddChoice("Everyone", PASSAGE_ALL)
    who_can_enter:Dock(TOP)
    who_can_enter:DockMargin(0, 7, 0, 0)

    local who_can_enter_btn = invite_panel:Add("DButton")
    who_can_enter_btn:SetEnabled(false)
    who_can_enter_btn:SetText("Confirm")
    who_can_enter_btn:Dock(TOP)
    who_can_enter_btn:DockMargin(0, 7, 0, 0)

    function who_can_enter_btn:Paint(w, h)
        surface.SetDrawColor(self:IsHovered() and btn_hover_color or color_white)
        surface.DrawRect(0, 0, w, h)
    end

    function who_can_enter_btn:DoClick()
        local _, new_state = who_can_enter:GetSelected()
        request_action_from_server(CL_NET_PASSAGE, room_number, new_state)
        root:Close()
    end

    function who_can_enter:OnSelect()
        who_can_enter_btn:SetEnabled(true)
    end
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
        for room_number, room in pairs(rooms) do
            if room.tenant == LocalPlayer():SteamID64() then
                is_client_renting = room_number
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