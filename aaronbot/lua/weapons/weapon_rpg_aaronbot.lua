AddCSLuaFile()

if CLIENT then
	killicon.AddFont("weapon_rpg_aaronbot", "HL2MPTypeDeath", "3", Color(255, 80, 0))
end

SWEP.PrintName = "#HL2_RPG"
SWEP.Spawnable = false
SWEP.Author = "Aaronek10"
SWEP.Purpose = "Should only be used internally by AaronBot nextbots!"
SWEP.ViewModel = "models/weapons/v_rpg.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"
SWEP.Weight = 5
SWEP.Primary = {Ammo = "RPG_Round", ClipSize = 1, DefaultClip = 1}
SWEP.Secondary = {Ammo = "None", ClipSize = -1, DefaultClip = -1}

function SWEP:Initialize()
	self:SetHoldType("rpg")
	if CLIENT then self:SetNoDraw(true) end
end

function SWEP:CanPrimaryAttack()
	return CurTime() >= self:GetNextPrimaryFire() and self:Clip1() > 0
end

function SWEP:CanSecondaryAttack() return false end

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	local owner = self:GetOwner()
	local rocket = ents.Create("rpg_missile")
	if IsValid(rocket) then
		rocket:SetPos(owner:GetShootPos())
		rocket:SetAngles(owner:GetAimVector():Angle())
		rocket:SetOwner(owner)
		rocket:Spawn()
		rocket:SetVelocity(owner:GetAimVector() * 1500)
	end
	self:GetParent():EmitSound(Sound("Weapon_RPG.Single"))
	self:SetClip1(0)
	self:SetNextPrimaryFire(CurTime() + 1.5)
	self:SetLastShootTime()
end

function SWEP:SecondaryAttack() end
function SWEP:Equip() end
function SWEP:OwnerChanged() end
function SWEP:OnDrop() end

function SWEP:Reload()
	self:SetClip1(self.Primary.ClipSize)
end

function SWEP:CanBePickedUpByNPCs() return true end
function SWEP:GetNPCBulletSpread(prof) return ({5, 4, 3, 2, 1})[prof + 1] end
function SWEP:GetNPCBurstSettings() return 1, 1, 1.5 end
function SWEP:GetNPCRestTimes() return 1.5, 3 end
function SWEP:GetCapabilities() return CAP_WEAPON_RANGE_ATTACK1 end
function SWEP:DrawWorldModel() end
