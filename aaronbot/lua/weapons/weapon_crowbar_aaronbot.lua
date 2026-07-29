AddCSLuaFile()

if CLIENT then
	killicon.AddFont("weapon_crowbar_aaronbot", "HL2MPTypeDeath", "6", Color(255, 80, 0))
end

SWEP.PrintName = "#HL2_Crowbar"
SWEP.Spawnable = false
SWEP.Author = "Aaronek10"
SWEP.Purpose = "Should only be used internally by AaronBot nextbots!"
SWEP.ViewModel = "models/weapons/v_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"
SWEP.Weight = 0
SWEP.DrawAmmo = false
SWEP.Primary = {Ammo = "None", ClipSize = -1, DefaultClip = -1, Automatic = true}
SWEP.Secondary = {Ammo = "None", ClipSize = -1, DefaultClip = -1}

local CROWBAR_RANGE = 75
local CROWBAR_REFIRE = 0.4
local BLUDGEON_HULL_DIM = 16
local g_bludgeonMins = Vector(-BLUDGEON_HULL_DIM, -BLUDGEON_HULL_DIM, -BLUDGEON_HULL_DIM)
local g_bludgeonMaxs = Vector(BLUDGEON_HULL_DIM, BLUDGEON_HULL_DIM, BLUDGEON_HULL_DIM)

function SWEP:Initialize()
	self:SetHoldType("melee")
	if CLIENT then
		self:SetNoDraw(true)
		self:DrawShadow(false)
	else
		hook.Add("Tick", self, function(self) self:WeaponThink() end)
	end
end

function SWEP:CanPrimaryAttack()
	return CurTime() >= self:GetNextPrimaryFire()
end

function SWEP:CanSecondaryAttack() return false end

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	local owner = self:GetOwner()
	local pos = owner:GetShootPos()
	local forward = owner:GetAimVector()
	local endpos = pos + forward * CROWBAR_RANGE
	local tr = util.TraceLine({start = pos, endpos = endpos, mask = MASK_SHOT_HULL, filter = owner})
	if tr.Fraction == 1 then
		tr = util.TraceHull({start = pos, endpos = endpos, mins = g_bludgeonMins, maxs = g_bludgeonMaxs, mask = MASK_SHOT_HULL, filter = owner})
	end
	if tr.Fraction < 1 and IsValid(tr.Entity) then
		local dmg = DamageInfo()
		dmg:SetAttacker(owner)
		dmg:SetInflictor(owner)
		dmg:SetDamageType(DMG_CLUB)
		dmg:SetDamage(25)
		dmg:SetDamagePosition(tr.HitPos)
		tr.Entity:DispatchTraceAttack(dmg, tr, forward)
	end
	self:GetOwner():EmitSound(Sound(tr.Fraction < 1 and "Weapon_Crowbar.Melee_Hit" or "Weapon_Crowbar.Single"))
	self:SetNextPrimaryFire(CurTime() + CROWBAR_REFIRE)
end

function SWEP:SecondaryAttack() end
function SWEP:Equip() end
function SWEP:OwnerChanged() end
function SWEP:OnDrop()
	if IsValid(self:GetOwner()) then self:SetupCondition() end
end
function SWEP:Reload() end
function SWEP:OnRemove()
	if CLIENT then return end
	self:OnDrop()
end

function SWEP:SetupCondition(condition)
	local owner = self:GetOwner()
	if self.COND and owner:HasCondition(self.COND) then owner:ClearCondition(self.COND) end
	self.COND = condition
	if condition and not owner:HasCondition(condition) then owner:SetCondition(condition) end
end

function SWEP:WeaponThink()
	if IsValid(self:GetOwner()) then self:SetupCondition(self:WeaponAttackCondition()) end
end

function SWEP:WeaponAttackCondition()
	local owner = self:GetOwner()
	local enemy = owner:GetEnemy()
	if not IsValid(enemy) then return 0 end
	local delta = enemy:WorldSpaceCenter() - owner:WorldSpaceCenter()
	if math.abs(delta.z) > 70 then return 39 end
	local forward = owner:GetAngles():Forward()
	delta.z = 0
	if delta:GetNormalized():Dot(forward) < 0.7 then return 40 end
	if delta:Length2D() > CROWBAR_RANGE then return 39 end
	return 23
end

function SWEP:CanBePickedUpByNPCs() return true end
function SWEP:GetNPCBulletSpread() return 0 end
function SWEP:GetNPCBurstSettings() return 1, 1, CROWBAR_REFIRE end
function SWEP:GetNPCRestTimes() return 0, 0 end
function SWEP:GetCapabilities() return CAP_WEAPON_MELEE_ATTACK1 end
function SWEP:DrawWorldModel() end
