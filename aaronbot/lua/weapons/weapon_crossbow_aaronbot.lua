AddCSLuaFile()

if CLIENT then
	killicon.AddFont("weapon_crossbow_aaronbot", "HL2MPTypeDeath", "1", Color(255, 80, 0))
end

SWEP.PrintName = "#HL2_Crossbow"
SWEP.Spawnable = false
SWEP.Author = "Aaronek10"
SWEP.Purpose = "Should only be used internally by AaronBot nextbots!"
SWEP.ViewModel = "models/weapons/v_crossbow.mdl"
SWEP.WorldModel = "models/weapons/w_crossbow.mdl"
SWEP.Weight = 4
SWEP.Primary = {Ammo = "XBowBolt", ClipSize = 1, DefaultClip = 1}
SWEP.Secondary = {Ammo = "None", ClipSize = -1, DefaultClip = -1}

function SWEP:Initialize()
	self:SetHoldType("crossbow")
	if CLIENT then self:SetNoDraw(true) end
end

function SWEP:CanPrimaryAttack()
	return CurTime() >= self:GetNextPrimaryFire() and self:Clip1() > 0
end

function SWEP:CanSecondaryAttack() return false end

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	local owner = self:GetOwner()
	local bolt = ents.Create("crossbow_bolt")
	if IsValid(bolt) then
		bolt:SetPos(owner:GetShootPos())
		bolt:SetAngles(owner:GetAimVector():Angle())
		bolt:SetOwner(owner)
		bolt:Spawn()
		bolt:SetVelocity(owner:GetAimVector() * 3500)
	end
	self:GetParent():EmitSound(Sound("Weapon_Crossbow.Single"))
	self:SetClip1(0)
	self:SetNextPrimaryFire(CurTime() + 0.75)
	self:SetLastShootTime()
end

function SWEP:SecondaryAttack() end
function SWEP:Equip() end
function SWEP:OwnerChanged() end
function SWEP:OnDrop() end

function SWEP:Reload()
	self:GetOwner():EmitSound(Sound("Weapon_Crossbow.Reload"))
	self:SetClip1(self.Primary.ClipSize)
end

function SWEP:CanBePickedUpByNPCs() return true end
function SWEP:GetNPCBulletSpread(prof) return ({5, 4, 3, 2, 1})[prof + 1] end
function SWEP:GetNPCBurstSettings() return 1, 1, 1 end
function SWEP:GetNPCRestTimes() return 1, 2 end
function SWEP:GetCapabilities() return CAP_WEAPON_RANGE_ATTACK1 end
function SWEP:DrawWorldModel() end
