AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

ENT.Model = "models/player/combine_super_soldier.mdl"
ENT.DefaultWeapon = nil
ENT.SpawnHealth = 100
ENT.MoveSpeed = 200
ENT.RunSpeed = 320
ENT.WalkSpeed = 100
ENT.CrouchSpeed = 120
ENT.AccelerationSpeed = 1000
ENT.DecelerationSpeed = 3000
ENT.AimSpeed = 360
ENT.LadderClimbSpeed = 200
ENT.CollisionBounds = {Vector(-16, -16, 0), Vector(16, 16, 72)}
ENT.CrouchCollisionBounds = {Vector(-16, -16, 0), Vector(16, 16, 36)}
ENT.CanCrouch = true
ENT.CanUseLadder = true
ENT.StepHeight = 18
ENT.JumpHeight = 50
ENT.MaxJumpToPosHeight = ENT.JumpHeight
ENT.DeathDropHeight = 200
ENT.DefaultGravity = 600
ENT.SolidMask = MASK_NPCSOLID
ENT.LineOfSightMask = MASK_BLOCKLOS
ENT.ForgetEnemyTime = 30
ENT.CloseEnemyDistance = 500
ENT.MaxSeeEnemyDistance = 3000
ENT.PathMinLookAheadDistance = 15
ENT.PathGoalTolerance = 25
ENT.PathGoalToleranceFinal = 25
ENT.PathRecompute = 5
ENT.DrawPath = CreateConVar("aaronbot_drawpath", 0, FCVAR_ARCHIVE)

function ENT:Initialize()
	self:SetModel(self.Model)
	self:SetSolidMask(self.SolidMask)
	self:SetCollisionGroup(COLLISION_GROUP_PLAYER)

	self:SetMaxHealth(self.SpawnHealth)
	self:SetHealth(self:GetMaxHealth())

	self:AddFlags(FL_OBJECT)

	self.BehaveInterval = 0
	self.m_Path = Path("Follow")
	self.m_PathPos = Vector()
	self.m_PathOptions = {}
	self.m_NavArea = navmesh.GetNearestNavArea(self:GetPos())
	self.m_Capabilities = 0
	self.m_ClassRelationships = {}
	self.m_EntityRelationships = {}
	self.m_EnemiesMemory = {}
	self.m_FootstepFoot = false
	self.m_FootstepTime = CurTime()
	self.m_LastMoveTime = CurTime()
	self.m_FallSpeed = 0
	self.m_UseNodeGraph = false
	self.m_TaskList = {}
	self.m_ActiveTasks = {}
	self.m_TaskCallbacks = {}
	self.m_Stuck = false
	self.m_StuckTime = CurTime()
	self.m_StuckTime2 = 0
	self.m_StuckPos = self:GetPos()
	self.m_HullType = HULL_HUMAN
	self.m_DuckHullType = HULL_TINY
	self.m_PassIsNPCCheck = true
	self.m_PitchAim = 0
	self.m_Conditions = {}

	self.loco:SetGravity(self.DefaultGravity)
	self.loco:SetAcceleration(self.AccelerationSpeed)
	self.loco:SetDeceleration(self.DecelerationSpeed)
	self.loco:SetStepHeight(self.StepHeight)
	self.loco:SetJumpHeight(self.JumpHeight)
	self.loco:SetDeathDropHeight(self.DeathDropHeight)

	self:SetupCollisionBounds()
	self:ReloadWeaponData()
	self:SetDesiredEyeAngles(self:GetAngles())
	self:SetupDefaultCapabilities()

	self:SetLagCompensated(true)

	self:AddCallback("PhysicsCollide", self.PhysicsObjectCollide)

	local wep = self:GetKeyValue("additionalequipment") or self.DefaultWeapon
	if wep then
		self:Give(wep)
	end
end

function ENT:GetFallDamage(speed)
	return 10
end

function ENT:OnKilled(dmg)
	if self:HasWeapon() then
		local wep = self:GetActiveLuaWeapon()

		if not dmg:IsDamageType(DMG_DISSOLVE) then
			if self:CanDropWeaponOnDie(wep) and wep:ShouldDropOnDie() then
				self:DropWeapon(nil, true)
			else
				wep:Remove()
			end
		else
			local wep = self:DropWeapon(nil, true)
			self:DissolveEntity(wep)
		end
	end

	if not self:RunTask("PreventBecomeRagdollOnKilled", dmg) then
		if dmg:IsDamageType(DMG_DISSOLVE) then self:DissolveEntity() end
		self:BecomeRagdoll(dmg)
	end

	self:RunTask("OnKilled", dmg)
	hook.Run("OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor())
end

function ENT:OnInjured(dmg)
	self:RunTask("OnInjured", dmg)
end

function ENT:KeyValue(key, value)
	self.KeyValues = self.KeyValues or {}
	self.KeyValues[key] = value
end

function ENT:GetKeyValue(key)
	return self.KeyValues and self.KeyValues[key]
end

function ENT:SetupDefaultCapabilities()
	self:CapabilitiesAdd(bit.bor(CAP_MOVE_GROUND, CAP_USE_WEAPONS))
end

function ENT:DissolveEntity(ent)
	ent = ent or self

	local dissolver = ents.Create("env_entity_dissolver")
	dissolver:SetMoveParent(ent)
	dissolver:SetSaveValue("m_flStartTime", 0)
	dissolver:Spawn()
	dissolver:AddEFlags(EFL_FORCE_CHECK_TRANSMIT)

	ent:SetSaveValue("m_flDissolveStartTime", 0)
	ent:SetSaveValue("m_hEffectEntity", dissolver)
	ent:AddFlags(FL_DISSOLVING)
end

include("motion.lua")
include("motion_stage1.lua")
include("weapons.lua")
include("enemy.lua")
include("behaviour.lua")
include("nodegraph_path.lua")
AddCSLuaFile("tasks.lua")
include("tasks.lua")

function ENT:SetCondition(condition) self.m_Conditions[condition] = true end
function ENT:HasCondition(condition) return self.m_Conditions[condition] or false end
function ENT:ClearCondition(condition) self.m_Conditions[condition] = nil end

function ENT:ConditionName(condition) return "" end
function ENT:ClearSchedule() end
function ENT:GetCurrentSchedule() return SCHED_NONE end
function ENT:IsCurrentSchedule(schedule) return schedule == SCHED_NONE end
function ENT:SetSchedule(schedule) end
function ENT:SetNPCState(state) end
function ENT:GetNPCState() return NPC_STATE_NONE end
function ENT:AddEntityRelationship(target, disposition, priority) self:SetEntityRelationship(target, disposition, priority) end
function ENT:AddRelationship(str)
	local explode = string.Explode(" ", str)
	local class = explode[1]
	if not class then return end
	local d = explode[2] == "D_LI" and D_LI or explode[2] == "D_HT" and D_HT or explode[2] == "D_ER" and D_ER or explode[2] == "D_FR" and D_FR
	local priority = tonumber(explode[3])
	self:SetClassRelationship(class, d or D_NU, priority or 0)
end
function ENT:Disposition(ent) return self:GetRelationship(ent) end

local meta = FindMetaTable("Entity")
if not meta.aaronbot_IsNPC then
	meta.aaronbot_IsNPC = meta.IsNPC
	meta.IsNPC = function(s)
		return s:aaronbot_IsNPC() or (s.AaronBot and s.m_PassIsNPCCheck) or false
	end
end
