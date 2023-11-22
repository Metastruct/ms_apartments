module("ms", package.seeall)
local tag = "ms_apartments"

local mesh, mtmp, inited, mat1
local function init()
	if inited then return end
	inited = true

	local sz = 8192 * 8
	local q = sz * (1 / 128)
	mesh = Mesh()

	local MeshVertexes = {
		{
			pos = sz * Vector(0.5, 0.5, 0),
			u = q,
			v = q,
			normal = Vector(0, 0, 1)
		},
		{
			pos = sz * Vector(0.5, -0.5, 0),
			u = q,
			v = 0,
			normal = Vector(0, 0, 1)
		},
		{
			pos = sz * Vector(-0.5, -0.5, 0),
			u = 0,
			v = 0,
			normal = Vector(0, 0, 1)
		},
		{
			pos = sz * Vector(-0.5, -0.5, 0),
			u = -q,
			v = -q,
			normal = Vector(0, 0, 1)
		},
		{
			pos = sz * Vector(-0.5, 0.5, 0),
			u = -q,
			v = 0,
			normal = Vector(0, 0, 1)
		},
		{
			pos = sz * Vector(0.5, 0.5, 0),
			u = 0,
			v = 0,
			normal = Vector(0, 0, 1)
		}
	}

	mesh:BuildFromTriangles(MeshVertexes)

	mat1 = CreateMaterial(tag, "VertexLitGeneric", util.KeyValuesToTable[[
	"a"
	{
		"$basetexture" "Nature/grassfloor002a"
	}
	]])

	mtmp = ClientsideModel("error.mdl", RENDERGROUP_OTHER)
	mtmp:SetModelScale(1)
end

local t = {
	model = "models/props_junk/sawblade001a.mdl",
	angle = Angle(0, 0, 0),
	pos = Vector(1745.7978515625, 1114.5703125, -9659.58984375)
}

local render = render

local clm
local center = landmark.get("apartments")
if not center then return end

local off = Vector(0, 0, center.z  - 256 )

local MAXDD = (2048 + 512) ^2

local function Draw3DSkyboxStuff(ep)
	init()

	if ep:DistToSqr(center) > MAXDD then return end
	if ep.z < off.z then return end
	if ep.z > off.z + 1255 then return end

	local mat = Matrix()
	local trans = off
	local rot = Angle(0, 0, 0)

	mat:Rotate(rot)
	mat:Translate(trans)
	mat:Scale(Vector(1, 1, 1))

	clm = clm and clm:IsValid() and clm or ClientsideModel(t.model, RENDERGROUP_OTHER)

	render.SetBlend(0)
	render.Model(t, clm)
	render.SetBlend(1)
	render.SetMaterial(mat1)
	cam.PushModelMatrix(mat)
	mesh:Draw()
	rot:RotateAroundAxis(rot:Up(), 240)

	if mtmp then
		mtmp:InvalidateBoneCache()
	end

	render.Model({
		model = "models/props_phx/huge/evildisc_corp.mdl",
		pos = Vector(0, 0, 0) + mat:GetTranslation(),
		angle = rot
	}, mtmp)

	cam.PopModelMatrix()
end

-- Find skyboxes

local skyboxes = {}

local files = file.Find("materials/skybox/*.vmt","GAME")

	for k,v in next, files do
		local skyname = v:match("^(.+)up%.vmt$")
		if skyname then
			skyboxes[skyname] = true
		end
	end

files = nil

local skyboxes_hdronly = {}

for name, _ in next, skyboxes do
	if name:find"_hdr$" then
		name = name:gsub("_hdr$", "")
		if skyboxes[name] then
			skyboxes_hdronly[name] = true
		end
	end
end

if IsValid(_G.dropship_ent) then
	local q = _G.dropship_ent
	_G.dropship_ent = nil
	q:Remove()
end

local mdl = "models/combine_dropship.mdl"

local m = ClientsideModel(mdl, RENDERMODE_NONE)
m:SetRenderMode(RENDERMODE_NONE)
m:SetNoDraw(true)

local scale = Vector(1, 1, 1)
_G.dropship_ent = m

local mat = Matrix()
mat:Scale(scale)
m:EnableMatrix("RenderMultiply", mat)

local skybox_apmnt = landmark.get("skybox_apmnt")
local view = {}
local recurs
view.drawviewmodel = false

local function RenderScene_Skybox(ep, ea, fov)
	if recurs then return end

	view.origin = skybox_apmnt
	view.angles = ea
	view.fov = fov

	recurs = true
	render.RenderView(view)
	recurs = false
end

Apartments.hkgrp:Add("RenderScene", function(ep, ea, ...)
	RenderScene_Skybox(ep, ea, ...)
end)

Apartments.hkgrp:Add("PreDrawOpaqueRenderables", function()
	Draw3DSkyboxStuff(EyePos(), EyeAngles())
end)