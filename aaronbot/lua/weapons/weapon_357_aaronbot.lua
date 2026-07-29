AddCSLuaFile()

if SERVER then
	util.AddNetworkString("weapon_357_aaronbot.muzzleflash")
else
	killicon.AddFont("weapon_357_aaronbot", "HL2MPTypeDeath", ".", Color(255, 80, 0))
end

SWEP.PrintName = "#HL2_357"
SWEP.Spawnable = false
SWEP.Author = "Aaronek10"
SWEP.Purpose = "Should only be used internally by AaronBot nextbots!"
SWEP.ViewModel = "models/weapons/v_357.mdl"
SWEP.WorldModel = "models/weapons/w_357.mdl"
SWEP.Weight = 3
SWEP.Primary = {Ammo = "357", ClipSize = 6, DefaultClip = 6}
SWEP.Secondary = {Ammo = "None", ClipSize = -1, DefaultClip = -1}

function SWEP:Initialize()
	self:SetHoldType("revolver")
	if CLIENT then self:SetNoDraw(true) end
end

function SWEP:CanPrimaryAttack()
	return CurTime() >= self:GetNextPrimaryFire() and self:Clip1() > 0
end

function SWEP:CanSecondaryAttack() return false end

local MAX_TRACE_LENGTH = 56756

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	local owner = self:GetOwner()
	self:FireBullets({Num = 1, Src = owner:GetShootPos(), Dir = owner:GetAimVector(), Spread = vector_origin, Distance = MAX_TRACE_LENGTH, AmmoType = self:GetPrimaryAmmoType(), Damage = 40, Force = 1, Attacker = owner})
	self:DoMuzzleFlash()
	self:GetParent():EmitSound(Sound("Weapon_357.Single"))
	self:SetClip1(self:Clip1() - 1)
	self:SetNextPrimaryFire(CurTime() + 0.75)
	self:SetLastShootTime()
end

function SWEP:DoMuzzleFlash()
	if SERVER then
		net.Start("weapon_357_aaronbot.muzzleflash", true)
		net.WriteEntity(self)
		net.SendPVS(self:GetPos())
	else
		local ef = EffectData()
		ef:SetEntity(self:GetParent())
		ef:SetAttachment(self:LookupAttachment("muzzle"))
		ef:SetScale(1)
		ef:SetFlags(4)
		util.Effect("MuzzleFlash", ef, false)
	end
end

function SWEP:GetTracerOrigin()
	return self:GetParent():GetAttachment(self:GetParent():LookupAttachment("muzzle")).Pos
end

if CLIENT then
	net.Receive("weapon_357_aaronbot.muzzleflash", function()
		local ent = net.ReadEntity()
		if IsValid(ent) and ent.DoMuzzleFlash then ent:DoMuzzleFlash() end
	end)
end

function SWEP:SecondaryAttack() end
function SWEP:Equip() end
function SWEP:OwnerChanged() end
function SWEP:OnDrop() end

function SWEP:Reload()
	self:GetOwner():EmitSound(Sound("Weapon_357.Reload"))
	self:SetClip1(self.Primary.ClipSize)
end

function SWEP:CanBePickedUpByNPCs() return true end
function SWEP:GetNPCBulletSpread(prof) return ({5, 4, 3, 2, 1})[prof + 1] end
function SWEP:GetNPCBurstSettings() return 1, 1, 0.75 end
function SWEP:GetNPCRestTimes() return 0.75, 1.25 end
function SWEP:GetCapabilities() return CAP_WEAPON_RANGE_ATTACK1 end
function SWEP:DrawWorldModel() end
