require("landmark")
if not landmark or not landmark.get("apartments") then return end

if SERVER then
	AddCSLuaFile("apartments/cl_apartments.lua")
	AddCSLuaFile("apartments/sh_privacy.lua")
	AddCSLuaFile("apartments/cl_skybox.lua")
	AddCSLuaFile("apartments/cl_door_signs.lua")
	AddCSLuaFile("apartments/cl_coloring.lua")

	include("apartments/sv_apartments.lua")
	include("apartments/sv_nocollide.lua")
end

if CLIENT then
	include("apartments/cl_apartments.lua")
	include("apartments/cl_skybox.lua")
	include("apartments/cl_door_signs.lua")
	include("apartments/cl_coloring.lua")
end

include("apartments/sh_privacy.lua")