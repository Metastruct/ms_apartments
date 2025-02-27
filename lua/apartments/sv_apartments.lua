
module("ms", package.seeall)
local tag = "ms_apartments"

util.AddNetworkString(tag)

local Apartments = Apartments or { NUM_ROOMS = 12 }
_M.Apartments = Apartments

local rooms = {}
local tenants = {}
local triggers = {}
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

local function log_event(log_type, ...)
    if not metalog or not metalog[log_type] then return end

    metalog[log_type]("Apartments", nil, ...)
end

local function net_broadcast_table(id, tbl)
    net.Start(tag)
    net.WriteUInt(id, 32)

    local payload = util.Compress(util.TableToJSON(tbl))
    net.WriteUInt(#payload, 32)
    net.WriteData(payload)

    net.Broadcast()
end

local function is_valid_room(room_number)
    if not room_number or not rooms[room_number] then
        return false
    end

    return true
end

local function is_valid_client_request(ply, id, room_number, state)
    local room = rooms[room_number]

    if id == CL_NET_RENT and state == 1 and tenants[ply:SteamID64()] then
        return false
    end

    if id ~= CL_NET_RENT and not room.tenant then
        return false
    end

    if room.tenant and room.tenant ~= ply:SteamID64() then
        return false
    end

    return true
end

local function get_room_entrance(trigger_pos, room_n)
    local box_bounds = Vector(370, 370, 5)
    local mins, maxs = trigger_pos - box_bounds, trigger_pos + box_bounds
    local near = ents.FindInBox(mins, maxs)

    local cmp_vec = Vector()
    trigger_pos.z = 0

    local doors = {}
    for _, ent in pairs(near) do
        if ent:GetClass() == "prop_door_rotating" then
            cmp_vec:Set(ent:GetPos())
            cmp_vec.z = 0

            doors[#doors + 1] = {ent, trigger_pos:DistToSqr(cmp_vec)}
        end
    end

    table.sort(doors, function(a, b) return a[2] > b[2] end)

    -- relies on the map
    return doors[1][1]
end

local function should_entity_be_in_room(ent, room)
    if not room.tenant then return true end

    local owner = ent.CPPIGetOwner and ent:CPPIGetOwner()
    if not IsValid(owner) or owner.Unrestricted then
        return true
    end

    if room.guests[owner:UserID()] then
        return true
    end

    local tenant = player.GetBySteamID64(room.tenant)
    if owner == tenant then
        return true
    end

    return false
end

local function should_player_be_in_room(ply, room)
    if room.tenant and not ply.Unrestricted then
        local tenant = player.GetBySteamID64(room.tenant)
        if ply == tenant then
            return true
        end

        if room.guests[ply:UserID()] then
            return true
        end

        if room.passage == PASSAGE_ALL then
            return true
        end

        if room.passage == PASSAGE_FRIENDS and tenant.IsFriend and tenant:IsFriend(ply) then
            return true
        end
    end

    return false
end

function Apartments.GetRooms()
    return rooms
end

function Apartments.GetTenants()
    return tenants
end

function Apartments.GetEntrances()
    return entrances
end

function Apartments.GetTriggers()
    return triggers
end

function Apartments.SetTenant(room_number, tenant)
    if not is_valid_room(room_number) or not tenant:IsPlayer() then return end

    local room = rooms[room_number]
    tenants[tenant:SteamID64()] = room_number
    room.tenant = tenant:SteamID64()
    room.passage = PASSAGE_GUESTS
    room.guests = {}

    for ply in pairs(room.trigger:GetPlayers()) do
        if not ply.Unrestricted and ply ~= tenant then
            ply:SetPos(landmark.get("apartments") or Vector())
        end
    end

    net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
    log_event("info", tenant:Nick(), "rented", room.name)
end

function Apartments.EvictTenant(tenant)
    local tenant_sid64 = type(tenant) == "string" and tenant or tenant:SteamID64()
    if not tenants[tenant_sid64] then return end

    local room = rooms[tenants[tenant_sid64]]
    tenants[tenant_sid64] = nil
    room.tenant = nil
    room.passage = PASSAGE_GUESTS
    room.guests = {}

    net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
    log_event("info", tenant.Nick and tenant:Nick() or tenant, "evicted from", room.name)
end

function Apartments.GetTenant(room_number)
    if not is_valid_room(room_number) then return end

    return rooms[room_number].tenant
end

function Apartments.Invite(room_number, guest)
    if not is_valid_room(room_number) or not guest:IsPlayer() then return end

    local room = rooms[room_number]
    -- either tabletojson or compress turns these keys into numbers, sid64 is too big
    room.guests[guest:UserID()] = true

    net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
    log_event("info", guest:Nick(), "invited to", room.name)
end

function Apartments.RevokeInvitation(room_number, guest)
    if not is_valid_room(room_number) or not guest:IsPlayer() then return end

    local room = rooms[room_number]
    local guest_uid = guest:UserID()

    if room.guests[guest_uid] then
        room.guests[guest_uid] = nil

        if room.trigger:GetPlayers()[guest] then
            guest:SetPos(landmark.get("apartments") or Vector())
        end

        net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
        log_event("info", "invite revoked for", guest:Nick(), "from", room.name)
    end
end

function Apartments.GetInvited(room_number, guest)
    if not is_valid_room(room_number) or guest and not guest:IsPlayer() then return end

    if not guest then
        return rooms[room_number].guests
    end

    return rooms[room_number].guests[guest:UserID()]
end

function Apartments.SetPassage(room_number, state)
    if not is_valid_room(room_number) then return end

    local room = rooms[room_number]
    room.passage = state

    if state < PASSAGE_ALL then
        local tenant = player.GetBySteamID64(room.tenant)
        for _, ply in room.trigger:GetPlayers() do
            if ply == tenant then continue end

            if state == PASSAGE_FRIENDS and tenant.IsFriend and not tenant:IsFriend(ply) then
                guesply:SetPos(landmark.get("apartments") or Vector())
            end

            if state == PASSAGE_GUESTS and not room.guests[ply:UserID()] then
                gueplyt:SetPos(landmark.get("apartments") or Vector())
            end
        end
    end

    net_broadcast_table(SV_NET_UPDATE_ROOMS, rooms)
    log_event("info", "passage set to", state, "for", room.name)
end

net.Receive(tag, function(_, ply)
    local id = net.ReadUInt(32)
    local room_number = net.ReadUInt(32)
    local state = net.ReadUInt(32)

    if not is_valid_room(room_number) or not is_valid_client_request(ply, id, room_number, state) then
        log_event("warn", "caught bad request from", ply:Nick())

        return
    end

    if id == CL_NET_RENT then
        if tobool(state) then
            Apartments.SetTenant(room_number, ply)
        else
            Apartments.EvictTenant(ply)
        end

        return
    end

    if id == CL_NET_INVITE then
        local guest = Player(net.ReadUInt(32))

        if tobool(state) then
            Apartments.Invite(room_number, guest)
        else
            Apartments.RevokeInvitation(room_number, guest)
        end

        return
    end

    if id == CL_NET_PASSAGE then
        Apartments.SetPassage(room_number, state)
    end
end)

hook.Add("PlayerFullyConnected", tag, function(ply)
    net.Start(tag)
    net.WriteUInt(SV_NET_UPDATE_BOTH, 32)

    local rooms_payload = util.Compress(util.TableToJSON(rooms))
    net.WriteUInt(#rooms_payload, 32)
    net.WriteData(rooms_payload)

    local entrances_payload = util.Compress(util.TableToJSON(entrances))
    net.WriteUInt(#entrances_payload, 32)
    net.WriteData(entrances_payload)

    net.Send(ply)

    local room_number = tenants[ply:SteamID64()]
    if room_number then
        local room = rooms[room_number]
        room._grace = nil

        log_event("info", room.name, "restored from grace")
    end
end)

hook.Add("PlayerDisconnected", tag, function(ply)
    local ply_sid64 = ply:SteamID64()
    local room_number = tenants[ply_sid64]
    if room_number then
        local room = rooms[room_number]
        room._grace = true

        log_event("info", room.name, "entering grace for 3 minutes")

        timer.Simple(60 * 3, function()
            if room._grace then
                room._grace = nil

                log_event("info", "grace expired for", room.name)
                Apartments.EvictTenant(ply_sid64)
            end
        end)
    end
end)

hook.Add("TriggerPreInclude", tag, function(place, TRIGGER)
    local place_match = string.match(place, "trigger_apartment_%d%d")
    if not place_match then return end

    function TRIGGER:Init()
        self:EnablePlayerCounting()
        self:EnablePlayerList()
        self:EnableEntityList()
        self:EnablePlayerInforming()
    end

    function TRIGGER:In(ent, is_player)
        local room = rooms[tonumber(self.place:match("%d%d"))]

        if not is_player and not should_entity_be_in_room(ent, room) then
            if ent.Dissolve then ent:Dissolve() end
            SafeRemoveEntityDelayed(ent, 3)

            return
        end

        if is_player and not should_player_be_in_room(ent, room) then
            ent:SetPos(landmark.get("apartments") or Vector())

            return
        end

        hook.Run("ApartmentEnter", ent, self, room)
    end

    function TRIGGER:Out(ent,is_player)
        if is_player then
            local room = rooms[self.place:match("%d%d")]
            hook.Run("ApartmentLeave", ent, self, room)
        end
    end

    return true -- overrides any includes, suppress missing logic warnings
end)

hook.Add("InitPostEntity", tag, function()
    rooms = {}
    tenants = {}
    triggers = {}
    entrances = {}

    for room_n = 1, Apartments.NUM_ROOMS do
        local as_two_digits = string.format("%02d", room_n)

        local trigger_name = "trigger_apartment_" .. as_two_digits
        local trigger = GetTrigger(trigger_name)

        local entrance = get_room_entrance(trigger:GetPos(), room_n)

        entrances[entrance:EntIndex()] = room_n
        triggers[trigger] = room_n

        rooms[room_n] = {
            name = "Apt. Room " .. as_two_digits,
            entrance = entrance,
            trigger = trigger,
            passage = PASSAGE_GUESTS,
            guests = {},
            -- tenant
        }
    end
end)

hook.Add("PostCleanupMap", tag, function()
    entrances = {}
    triggers = {}

    for room_n = 1, Apartments.NUM_ROOMS do
        local room = rooms[room_n]
        local as_two_digits = string.format("%02d", room_n)

        local trigger_name = "trigger_apartment_" .. as_two_digits
        local trigger = GetTrigger(trigger_name)

        local entrance = get_room_entrance(trigger:GetPos(), room_n)

        room.trigger = trigger
        room.entrance = entrance

        entrances[entrance:EntIndex()] = room_n
        triggers[trigger] = room_n
    end

    net_broadcast_table(SV_NET_UPDATE_ENTRANCES, entrances)
end)