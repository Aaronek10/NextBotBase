AddCSLuaFile()

if SERVER then
	util.AddNetworkString("weapon_ar2_aaronbot.muzzleflash")
else
	killicon.AddFont("weapon_ar2_aaronbot", "HL2MPTypeDeath", "2", Color(255, 80, 0))
end

SWEP.PrintName = "#HL2_Pulse_Rifle"
SWEP.Spawnable = false
SWEP.Author = "Aaronek10"
SWEP.Purpose = "Should only be used internally by AaronBot nextbots!"
SWEP.ViewModel = "models/weapons/v_irifle.mdl"
SWEP.WorldModel = "models/weapons/w_irifle.mdl"
SWEP.Weight = 5
SWEP.Primary = {Ammo = "AR2", ClipSize = 30, DefaultClip = 30, Automatic = true}
SWEP.Secondary = {Ammo = "AR2AltFire", ClipSize = -1, DefaultClip = -1}

function SWEP:Initialize()
	self:SetHoldType("ar2")
	if CLIENT then self:SetNoDraw(true) end
end

function SWEP:CanPrimaryAttack()
	return CurTime() >= self:GetNextPrimaryFire() and self:Clip1() > 0
end

function SWEP:CanSecondaryAttack()
	return CurTime() >= self:GetNextSecondaryFire()
end

local MAX_TRACE_LENGTH = 56756

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	local owner = self:GetOwner()
	self:FireBullets({Num = 1, Src = owner:GetShootPos(), Dir = owner:GetAimVector(), Spread = vector_origin, Distance = MAX_TRACE_LENGTH, AmmoType = self:GetPrimaryAmmoType(), Damage = 8, Force = 1, Attacker = owner, TracerName = "AR2Tracer"})
	self:DoMuzzleFlash()
	self:GetParent():EmitSound(Sound("Weapon_AR2.NPC_Single"))
	self:SetClip1(self:Clip1() - 1)
	self:SetNextPrimaryFire(CurTime() + 0.1)
	self:SetLastShootTime()
end

function SWEP:DoMuzzleFlash()
	if SERVER then
		net.Start("weapon_ar2_aaronbot.muzzleflash", true)
		net.WriteEntity(self)
		net.SendPVS(self:GetPos())
	else
		local ef = EffectData()
		ef:SetEntity(self:GetParent())
		ef:SetAttachment(self:LookupAttachment("muzzle"))
		ef:SetScale(1)
		ef:SetFlags(5)
		util.Effect("MuzzleFlash", ef, false)
	end
end

function SWEP:GetTracerOrigin()
	return self:GetParent():GetAttachment(self:GetParent():LookupAttachment("muzzle")).Pos
end

if CLIENT then
	net.Receive("weapon_ar2_aaronbot.muzzleflash", function()
		local ent = net.ReadEntity()
		if IsValid(ent) and ent.DoMuzzleFlash then ent:DoMuzzleFlash() end
	end)
end

function SWEP:SecondaryAttack()
	if not self:CanSecondaryAttack() then return end
	self:EmitSound(Sound("Weapon_AR2.NPC_Double"))
	local pos = self:GetOwner():GetShootPos()
	local vel = self:GetOwner():GetAimVector() * 1000
	local ball = ents.Create("prop_combine_ball")
	if IsValid(ball) then
		ball:SetPos(pos)
		ball:SetOwner(self:GetOwner())
		ball:Spawn()
		ball:Activate()
		ball:SetSaveValue("m_nState", 2)
		ball:EmitSound("NPC_CombineBall.Launch")
		if IsValid(ball:GetPhysicsObject()) then
			ball:GetPhysicsObject():SetVelocity(vel)
			ball:GetPhysicsObject():AddGameFlag(FVPHYSICS_WAS_THROWN)
		end
	end
	self:SetNextSecondaryFire(CurTime() + 1)
end

function SWEP:Equip() end
function SWEP:OwnerChanged() end
function SWEP:OnDrop() end

function SWEP:Reload()
	self:GetOwner():EmitSound(Sound("Weapon_AR2.NPC_Reload"))
	self:SetClip1(self.Primary.ClipSize)
end

function SWEP:DoImpactEffect(tr, dmg)
	local data = EffectData()
	data:SetOrigin(tr.HitPos + tr.HitNormal)
	data:SetNormal(tr.HitNormal)
	util.Effect("AR2Impact", data)
end

function SWEP:CanBePickedUpByNPCs() return true end
function SWEP:GetNPCBulletSpread(prof) return ({7, 5, 3, 5/3, 1})[prof + 1] end
function SWEP:GetNPCBurstSettings() return 2, 5, 0.1 end
function SWEP:GetNPCRestTimes() return 0.33, 0.66 end
function SWEP:GetCapabilities() return CAP_WEAPON_RANGE_ATTACK1 end
function SWEP:DrawWorldModel() end
