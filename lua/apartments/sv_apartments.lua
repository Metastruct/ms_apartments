module("ms", package.seeall)
local tag = "ms_apartments"

local function log_event(log_type, ...)
	if not metalog or not metalog[log_type] then return end

	metalog[log_type]("Apartments", nil, ...)
end

local kick_pos
local function kick_player_out(ply)
	kick_pos = kick_pos or landmark.get("apartments") or Vector()
	ply:SetPos(kick_pos)

	ply:ChatPrint("You're not welcome here!")
	ply:EmitSound("vo/npc/female01/gethellout.wav")
end

local skid_kick = SkidBait and SkidBait.SkidKick or function(ply)
	ply:Kick()
end

local function should_entity_be_in_trigger(ent, trigger)
	local owner = ent.CPPIGetOwner and ent:CPPIGetOwner()
	if not IsValid(owner) then return true end
	if owner.Unrestricted then return true end

	local room_n = Apartments.Triggers[trigger]
	local room = Apartments.List[room_n]

	if not room.tenant or owner == room.tenant or room.invitees[owner:SteamID64()] then return true end
	if room.friendly and room.tenant.IsFriend and room.tenant:IsFriend(owner) then return true end

	return false
end

-- Setting up all the individual apartment triggers
local function setup_triggers(place, TRIGGER)
	local place_match = string.match(place, "trigger_apartment_%d%d")
	if not place_match then return end

	function TRIGGER:Init()
		self:EnablePlayerCounting()
		self:EnablePlayerList()
		self:EnableEntityList()
		self:EnablePlayerInforming()
	end

	function TRIGGER:In(ent, is_player)
		if not is_player then
			if should_entity_be_in_trigger(ent, self) then return end

			if ent.Dissolve then ent:Dissolve() end
			SafeRemoveEntityDelayed(ent, 3)

			return
		end

		local index = tonumber(self.place:match"%d%d")
		local room = Apartments.List[index]

		if not room or not room.tenant then return end
		if ent.Unrestricted or room.public or ent == room.tenant then return end
		if room.invitees[ent:SteamID64()] or (room.friendly and room.tenant.IsFriend and room.tenant:IsFriend(ent)) then return end

		kick_player_out(ent)
	end

	function TRIGGER:Out()

	end

	return true -- overrides any includes, suppress missing logic warnings
end

hook.Add("TriggerPreInclude", "apartment_triggers", setup_triggers)

-- What has changed?
local NET_RENT = 0
local NET_INVITE = 1
local NET_INFO = 2

-- The change itself
local NET_KICK = 0
local NET_ADMIT = 1
local NET_SET_PUBLIC = 2
local NET_INVITE_FRIENDS = 3

local function network_rent_change(ply, room_n, change)
	net.Start(tag)
	net.WriteInt(NET_RENT, 3)
	net.WriteInt(room_n, 5)
	net.WriteInt(change, 3)
	net.WriteEntity(ply)
	net.Broadcast()
end

local function network_info(broadcast, ply)
	local entrances_networkable = {}
	for entrance, room_n in pairs(Apartments.Entrances) do
		entrances_networkable[entrance:EntIndex()] = room_n
	end

	local tenants_networkable = {}
	for tenant, room_n in pairs(Apartments.Tenants) do
		tenants_networkable[tenant:EntIndex()] = room_n
	end

	entrances_networkable = util.TableToJSON(entrances_networkable)
	tenants_networkable = util.TableToJSON(tenants_networkable)

	entrances_networkable = util.Compress(entrances_networkable)
	tenants_networkable = util.Compress(tenants_networkable)

	local entrances_size = #entrances_networkable
	local tenants_size = #tenants_networkable
	net.Start(tag)
	net.WriteInt(NET_INFO, 3)
	net.WriteUInt(entrances_size, 16)
	net.WriteData(entrances_networkable, entrances_size)
	net.WriteUInt(tenants_size, 16)
	net.WriteData(tenants_networkable, tenants_size)
	net[broadcast and "Broadcast" or "Send"](ply)
end

local function is_tampering(sender, room)
	if not Apartments.Tenants[sender] or room.tenant ~= sender then
		log_event("warn", "Sending off", sender, "for tampering!")
		skid_kick(sender)

		return true
	end
end

local function receive_rent_change(sender, room_n, change)
	local room = Apartments.List[room_n]

	if change == NET_ADMIT then
		if Apartments.Tenants[sender] or room.tenant then return end
		Apartments.SetTenant(room_n, sender)

		return
	end

	if change == NET_KICK then
		if is_tampering(sender, room) then return end
		Apartments.Evict(sender)
	end
end

local function receive_invite_change(sender, room_n, change, target)
	local room = Apartments.List[room_n]

	if change == NET_ADMIT then
		if is_tampering(sender, room) then return end
		Apartments.Invite(room_n, target)

		return
	end

	if change == NET_KICK then
		if is_tampering(sender, room) then return end
		Apartments.Kick(room_n, target)

		return
	end

	if change == NET_SET_PUBLIC then
		if is_tampering(sender, room) then return end
		room.public = not room.public

		sender:ChatPrint("Your room is now " .. (room.public and "public" or "private") .. ".")
		log_event("info", room.name, "has been set to", room.public and "public" or "private")

		if room.public then return end
		for to_kick, _ in pairs(room.trigger:GetPlayers()) do
			if to_kick.Unrestricted or to_kick == sender or room.invitees[to_kick:SteamID64()] then continue end

			kick_player_out(to_kick)
		end

		return
	end

	if change == NET_INVITE_FRIENDS then
		if is_tampering(sender, room) then return end
		Apartments.List[room_n].friendly = not Apartments.List[room_n].friendly

		sender:ChatPrint("Your room is now " .. (room.friendly and "open to friends" or "no longer open to friends") .. ".")
		log_event("info", room.name, "has been set to", room.friendly and "friendly" or "not friendly")

		if room.friendly then return end
		for to_kick, _ in pairs(room.trigger:GetPlayers()) do
			if to_kick.Unrestricted or to_kick == sender or room.invitees[to_kick:SteamID64()] then continue end

			kick_player_out(to_kick)
		end
	end
end

net.Receive(tag, function(_, sender)
	local net_type = net.ReadInt(3)
	local room_n = net.ReadInt(5)
	local change = net.ReadInt(3)

	local target
	if net_type == NET_INVITE and change <= NET_ADMIT then target = net.ReadEntity() end

	if net_type == NET_RENT then
		receive_rent_change(sender, room_n, change, target)

		return
	end

	if net_type == NET_INVITE then
		receive_invite_change(sender, room_n, change, target)
	end
end)

local box_bounds = Vector(370, 370, 5)
local function get_entrance(trigger_pos, room_n)
	local mins, maxs = trigger_pos - box_bounds, trigger_pos + box_bounds
	local near = ents.FindInBox(mins, maxs)

	local cmp_vec = Vector()
	trigger_pos.z = 0

	local doors = {}
	for _, ent in pairs(near) do
		if ent:GetClass() ~= "prop_door_rotating" then continue end

		cmp_vec:Set(ent:GetPos())
		cmp_vec.z = 0

		doors[#doors + 1] = {ent, trigger_pos:DistToSqr(cmp_vec)}
	end

	table.sort(doors, function(a, b) return a[2] > b[2] end)

	return doors[1][1]
end

local function post_cleanup(force)
	for room_n = 1, Apartments.NUM_ROOMS do
		local entry = Apartments.List[room_n]

		if not entry then continue end
		if not force and entry.trigger ~= NULL and entry.entrance ~= NULL then continue end

		local as_two_digits = string.format("%02d", room_n)

		local trigger_name = "trigger_apartment_" .. as_two_digits
		local trigger = GetTrigger(trigger_name)

		local entrance = get_entrance(trigger:GetPos(), room_n)

		entry.trigger = trigger
		entry.entrance = entrance

		Apartments.Entrances[entrance] = room_n
		Apartments.Triggers[trigger] = room_n
	end

	network_info(true)
end

hook.Add("PostSpawnLuaTriggers", tag, post_cleanup)
hook.Add("PlayerFullyConnected", tag, function(ply)
	network_info(false, ply)
end)

local function check_for_bad_doors()
	local found_bad
	for ent, _ in pairs(Apartments.Entrances) do
		if not IsValid(ent) then found_bad = true continue end
	end

	if not found_bad then return end

	Apartments.Entrances = {}
	post_cleanup(true)
end

timer.Create(tag, 30, 0, check_for_bad_doors)

function Apartments.Evict(ply)
	if not ply:IsPlayer() then return "Not a player!" end
	if not Apartments.Tenants[ply] then return "This player isn't renting an apartment!" end

	local room_number = Apartments.Tenants[ply]
	local room = Apartments.List[room_number]

	Apartments.Tenants[ply] = nil

	network_rent_change(room.tenant, room_number, NET_KICK)

	room.invitees = {}
	room.tenant = nil
	room.public = false
	room.friendly = false

	ply:ChatPrint("You no longer own " .. room.name .. "!")
	ply:EmitSound("doors/door1_stop.wav")
	log_event("info", "Evicted", ply, "from", room.name)

	return true
end

function Apartments.SetTenant(room_number, ply)
	if room_number < 1 or room_number > Apartments.NUM_ROOMS then return "Invalid room number!" end
	if not ply:IsPlayer() then return "Not a player!" end

	local room = Apartments.List[room_number]
	room.tenant = ply

	Apartments.Tenants[ply] = room_number

	network_rent_change(ply, room_number, NET_ADMIT)

	for to_kick, _ in pairs(room.trigger:GetPlayers()) do
		if to_kick.Unrestricted or to_kick == ply then continue end

		kick_player_out(to_kick)
	end

	ply:ChatPrint("You now own " .. room.name .. "!")
	ply:EmitSound("doors/handle_pushbar_locked1.wav")
	log_event("info", "New tenant", ply, room.name)

	return true
end

function Apartments.GetTenant(room_number)
	if room_number < 1 or room_number > Apartments.NUM_ROOMS then return "Invalid room number!" end
	local room = Apartments.List[room_number]

	return room.tenant
end

function Apartments.Kick(room_number, ply)
	if room_number < 1 or room_number > Apartments.NUM_ROOMS then return "Invalid room number!" end
	if not ply:IsPlayer() then return "Not a player!" end

	local room = Apartments.List[room_number]
	if not room.invitees[ply:SteamID64()] then return "This player is not invited!" end
	room.invitees[ply:SteamID64()] = nil

	if room.trigger:GetPlayers()[ply] then
		kick_player_out(ply)
	end

	ply:ChatPrint(room.tenant:Nick() .. " has kicked you out of their apartment!")
	log_event("info", room.tenant, "revoked invite to", room.name, "for", ply)

	return true
end

function Apartments.Invite(room_number, ply)
	if room_number < 1 or room_number > Apartments.NUM_ROOMS then return "Invalid room number!" end
	if not ply:IsPlayer() then return "Not a player!" end

	local room = Apartments.List[room_number]

	if room.invitees[ply:SteamID64()] then return end
	room.invitees[ply:SteamID64()] = true

	ply:ChatPrint(room.tenant:Nick() .. " has invited you to their apartment!")
	ply:EmitSound("vo/Streetwar/Alyx_gate/al_hey.wav")
	log_event("info", room.tenant, "invited", ply, "to", room.name)

	return true
end

hook.Add("PlayerDisconnected", tag, function(ply)
	if not Apartments.Tenants[ply] then return end
	Apartments.Evict(ply)
end)

local last_knocked = {}
local function knock_on_entrance(entrance)
	for i = 1, 3 do
		timer.Simple(i * .25, entrance.EmitSound, entrance, "physics/wood/wood_box_impact_soft1.wav", 80)
	end
end

hook.Add("PlayerUse", tag, function(ply, ent)
	local room_n = Apartments.Entrances[ent]
	if not room_n then return end

	local room = Apartments.List[room_n]
	if room.tenant and not ply.Unrestricted and not room.public and room.tenant ~= ply
	and not room.invitees[ply:SteamID64()] and not (room.friendly and ply.IsFriend and room.tenant:IsFriend(ply)) then
		if not last_knocked[ply] then last_knocked[ply] = CurTime() - 20 end
		if last_knocked[ply] + 20 > CurTime() then return false end
		last_knocked[ply] = CurTime()

		room.tenant:ChatPrint(ply:Nick() .. " is at your apartment door!")
		knock_on_entrance(ent)

		return false
	end
end)