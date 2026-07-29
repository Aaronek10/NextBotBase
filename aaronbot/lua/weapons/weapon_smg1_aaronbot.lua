AddCSLuaFile()

if SERVER then
	util.AddNetworkString("weapon_smg1_aaronbot.muzzleflash")
else
	killicon.AddFont("weapon_smg1_aaronbot", "HL2MPTypeDeath", "/", Color(255, 80, 0))
end

SWEP.PrintName = "#HL2_SMG1"
SWEP.Spawnable = false
SWEP.Author = "Aaronek10"
SWEP.Purpose = "Should only be used internally by AaronBot nextbots!"
SWEP.ViewModel = "models/weapons/v_smg1.mdl"
SWEP.WorldModel = "models/weapons/w_smg1.mdl"
SWEP.Weight = 3
SWEP.Primary = {Ammo = "SMG1", ClipSize = 45, DefaultClip = 45, Automatic = true}
SWEP.Secondary = {Ammo = "SMG1_Grenade", ClipSize = -1, DefaultClip = -1}

function SWEP:Initialize()
	self:SetHoldType("smg")
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
	self:FireBullets({Num = 1, Src = owner:GetShootPos(), Dir = owner:GetAimVector(), Spread = vector_origin, Distance = MAX_TRACE_LENGTH, AmmoType = self:GetPrimaryAmmoType(), Damage = 4, Force = 1, Attacker = owner})
	self:DoMuzzleFlash()
	self:GetParent():EmitSound(Sound("Weapon_SMG1.NPC_Single"))
	self:SetClip1(self:Clip1() - 1)
	self:SetNextPrimaryFire(CurTime() + 0.075)
	self:SetLastShootTime()
end

function SWEP:DoMuzzleFlash()
	if SERVER then
		net.Start("weapon_smg1_aaronbot.muzzleflash", true)
		net.WriteEntity(self)
		net.SendPVS(self:GetPos())
	else
		local ef = EffectData()
		ef:SetEntity(self:GetParent())
		ef:SetAttachment(self:LookupAttachment("muzzle"))
		ef:SetScale(1)
		ef:SetFlags(2)
		util.Effect("MuzzleFlash", ef, false)
	end
end

function SWEP:GetTracerOrigin()
	return self:GetParent():GetAttachment(self:GetParent():LookupAttachment("muzzle")).Pos
end

if CLIENT then
	net.Receive("weapon_smg1_aaronbot.muzzleflash", function()
		local ent = net.ReadEntity()
		if IsValid(ent) and ent.DoMuzzleFlash then ent:DoMuzzleFlash() end
	end)
end

function SWEP:SecondaryAttack()
	if not self:CanSecondaryAttack() then return end
	if self:WaterLevel() == 3 then self:SetNextSecondaryFire(CurTime() + 0.5) return end
	self:GetParent():EmitSound(Sound("Weapon_SMG1.Double"))
	local owner = self:GetOwner()
	local grenade = ents.Create("grenade_ar2")
	grenade:SetPos(owner:GetShootPos())
	grenade:SetVelocity(owner:GetEyeAngles():Forward() * 1000)
	grenade:SetOwner(owner)
	grenade:Spawn()
	grenade:SetSaveValue("m_bIsLive", false)
	grenade:SetSaveValue("m_fSpawnTime", CurTime())
	grenade:SetSaveValue("m_hThrower", owner)
	timer.Simple(0.1, function() if grenade:IsValid() then grenade:SetSaveValue("m_bIsLive", true) end end)
	self:SetNextPrimaryFire(CurTime() + 0.5)
	self:SetNextSecondaryFire(CurTime() + 1)
end

function SWEP:Equip() end
function SWEP:OwnerChanged() end
function SWEP:OnDrop() end

function SWEP:Reload()
	self:GetOwner():EmitSound(Sound("Weapon_SMG1.NPC_Reload"))
	self:SetClip1(self.Primary.ClipSize)
	self:SetNextSecondaryFire(CurTime() + 1.5)
end

function SWEP:CanBePickedUpByNPCs() return true end
function SWEP:GetNPCBulletSpread(prof) return ({7, 5, 10/3, 5/3, 1})[prof + 1] end
function SWEP:GetNPCBurstSettings() return 2, 5, 0.075 end
function SWEP:GetNPCRestTimes() return 0.33, 0.66 end
function SWEP:GetCapabilities() return CAP_WEAPON_RANGE_ATTACK1 end
function SWEP:DrawWorldModel() end
