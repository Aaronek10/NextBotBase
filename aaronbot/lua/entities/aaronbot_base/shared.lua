ENT.Base = "base_nextbot"

ENT.PrintName = "AaronBot Base"
ENT.Author = "Aaronek10"
ENT.Purpose = "Create your own nextbots using this base"

ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.AutomaticFrameAdvance = true
ENT.Spawnable = false

ENT.AaronBot = true

ENT.ViewOffset = Vector(0, 0, 64)
ENT.CrouchViewOffset = Vector(0, 0, 32)
ENT.ViewPunchLength = 0.5

--[[
	IdleActivityTranslations maps ACT_MP_* activities to the activity/sequence
	the bot should actually play. Override per-class for non-player animsets
	(e.g. zombie). Values may be a number (ACT_*) or a function(self) -> number.
]]
local IdleActivity = ACT_HL2MP_IDLE
ENT.IdleActivity = IdleActivity
ENT.IdleActivityTranslations = {
	[ACT_MP_STAND_IDLE] = IdleActivity,
	[ACT_MP_WALK] = IdleActivity + 1,
	[ACT_MP_RUN] = IdleActivity + 2,
	[ACT_MP_CROUCH_IDLE] = IdleActivity + 3,
	[ACT_MP_CROUCHWALK] = IdleActivity + 4,
	[ACT_MP_ATTACK_STAND_PRIMARYFIRE] = IdleActivity + 5,
	[ACT_MP_ATTACK_CROUCH_PRIMARYFIRE] = IdleActivity + 5,
	[ACT_MP_RELOAD_STAND] = IdleActivity + 6,
	[ACT_MP_RELOAD_CROUCH] = IdleActivity + 7,
	[ACT_MP_JUMP] = ACT_HL2MP_JUMP_SLAM,
	[ACT_MP_SWIM] = IdleActivity + 9,
	[ACT_LAND] = ACT_LAND,
}

local AddNetworkVar = function(type, slot, name)
	ENT["Set" .. name] = function(self, value)
		self["SetDT" .. type](self, slot, value)
	end
	ENT["Get" .. name] = function(self)
		return self["GetDT" .. type](self, slot)
	end
end

AddNetworkVar("Entity", 0, "ActiveWeapon")
AddNetworkVar("Bool", 0, "Crouching")
AddNetworkVar("Int", 0, "WeaponClip1")
AddNetworkVar("Int", 1, "WeaponClip2")
AddNetworkVar("Int", 2, "WeaponMaxClip1")
AddNetworkVar("Int", 3, "WeaponMaxClip2")
AddNetworkVar("Float", 0, "ViewPunchTime")
AddNetworkVar("Angle", 0, "ViewPunchAngle")

function ENT:GetEyeAngles()
	local pitch = self:GetPoseParameter("aim_pitch")

	if CLIENT then
		local pitchid = self:LookupPoseParameter("aim_pitch")
		if pitchid != -1 then
			pitch = math.Remap(pitch, 0, 1, self:GetPoseParameterRange(pitchid))
		end
	end

	local ang = self:GetAngles()
	ang.p = pitch
	return ang
end

function ENT:GetViewPunchAngles()
	local vptime = self:GetViewPunchTime() + self.ViewPunchLength - CurTime()
	if vptime < 0 or vptime > self.ViewPunchLength then return Angle() end

	vptime = vptime / self.ViewPunchLength
	local vang = self:GetViewPunchAngle()
	local afr

	if vptime >= 0.6 then
		local fr = (1 - vptime) / 0.4
		afr = 1 - (1 - fr) ^ 2
	else
		local fr = vptime / 0.6
		afr = fr ^ 2
	end

	return Angle(vang.p * afr, vang.y * afr, vang.r * afr)
end

function ENT:HasWeapon()
	return IsValid(self:GetActiveWeapon())
end

function ENT:GetShootPos()
	return self:GetPos() + (self:IsCrouching() and self.CrouchViewOffset or self.ViewOffset)
end

function ENT:IsCrouching()
	return self:GetCrouching()
end
