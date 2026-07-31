-- Lua analogs to engine weapons (rebranded)
local EngineAnalogs = {
	weapon_ar2 = "weapon_ar2_aaronbot",
	weapon_smg1 = "weapon_smg1_aaronbot",
	weapon_pistol = "weapon_pistol_aaronbot",
	weapon_357 = "weapon_357_aaronbot",
	weapon_crossbow = "weapon_crossbow_aaronbot",
	weapon_rpg = "weapon_rpg_aaronbot",
	weapon_shotgun = "weapon_shotgun_aaronbot",
	weapon_crowbar = "weapon_crowbar_aaronbot",
	weapon_stunstick = "weapon_stunstick_aaronbot",
}

local EngineAnalogsReverse = {}
for k, v in pairs(EngineAnalogs) do EngineAnalogsReverse[v] = k end

--[[------------------------------------
	Holdtype for nextbot animations.
	Prefer SWEP.HoldType (ARC9 always sets it); GetHoldType() often returns "ar2".
--]]------------------------------------
function ENT:ResolveWeaponHoldType(wep)
	if not IsValid(wep) then return "normal" end

	if isstring(wep.AaronBotHoldType) and wep.AaronBotHoldType ~= "" then
		return wep.AaronBotHoldType
	end

	if isstring(wep.HoldType) and wep.HoldType ~= "" then
		return wep.HoldType
	end

	local ht = wep:GetHoldType()
	if isstring(ht) and ht ~= "" then
		return ht
	end

	return "ar2"
end

function ENT:ApplyWeaponHoldType(wep)
	wep = wep or self:GetActiveLuaWeapon()
	if not IsValid(wep) then return end

	local ht = self:ResolveWeaponHoldType(wep)

	local ownerWep = self:GetActiveWeapon()
	if IsValid(ownerWep) and ownerWep ~= wep then
		local ht2 = self:ResolveWeaponHoldType(ownerWep)
		if ht2 and ht2 ~= "" then ht = ht2 end
	end

	if wep.SetHoldType then wep:SetHoldType(ht) end
	if wep.SetWeaponHoldType then wep:SetWeaponHoldType(ht) end
	self.m_WeaponHoldType = ht
	return ht
end

function ENT:Give(wepname)
	local wep = ents.Create(wepname)

	if IsValid(wep) then
		if not wep:IsScripted() and not EngineAnalogs[wepname] then
			wep:Remove()
			return NULL
		end

		wep:SetPos(self:GetPos())
		wep:SetOwner(self)
		wep:Spawn()
		wep:Activate()

		return self:SetupWeapon(wep)
	end
end

function ENT:GetActiveLuaWeapon()
	return self.m_ActualWeapon or NULL
end

function ENT:SetupWeapon(wep)
	if not IsValid(wep) or wep == self:GetActiveWeapon() then return end

	if not wep:IsScripted() and not EngineAnalogs[wep:GetClass()] then return end

	if self:HasWeapon() then
		self:GetActiveWeapon():Remove()
	end

	ProtectedCall(function() self:OnWeaponEquip(wep) end)

	self:SetActiveWeapon(wep)

	if EngineAnalogs[wep:GetClass()] then
		local actwep = ents.Create(EngineAnalogs[wep:GetClass()])
		actwep:SetOwner(self)
		actwep:Spawn()
		actwep:Activate()
		actwep:SetParent(wep)
		actwep:SetLocalPos(vector_origin)
		actwep:SetLocalAngles(angle_zero)
		actwep:PhysicsDestroy()
		actwep:AddSolidFlags(FSOLID_NOT_SOLID)
		actwep:AddEffects(EF_BONEMERGE)
		actwep:SetTransmitWithParent(true)

		actwep:SetClip1(wep:Clip1())
		actwep:SetClip2(wep:Clip2())

		hook.Add("Think", actwep, function(self)
			if IsValid(wep) then
				wep:SetClip1(self:Clip1())
				wep:SetClip2(self:Clip2())
			end
		end)

		hook.Add("EntityRemoved", actwep, function(self, ent)
			if ent == wep then self:Remove() end
		end)
		actwep:DeleteOnRemove(wep)

		self.m_ActualWeapon = actwep
	else
		self.m_ActualWeapon = wep
	end

	local actwep = self:GetActiveLuaWeapon()
	self:ApplyWeaponHoldType(actwep)

	self:ReloadWeaponData()

	wep:SetVelocity(vector_origin)
	wep:RemoveSolidFlags(FSOLID_TRIGGER)
	wep:SetOwner(self)
	wep:RemoveEffects(EF_ITEM_BLINK)
	wep:PhysicsDestroy()

	wep:SetParent(self)
	wep:SetMoveType(MOVETYPE_NONE)
	wep:AddEffects(EF_BONEMERGE)
	wep:AddSolidFlags(FSOLID_NOT_SOLID)
	wep:SetLocalPos(vector_origin)
	wep:SetLocalAngles(angle_zero)
	wep:SetTransmitWithParent(true)

	ProtectedCall(function() actwep:OwnerChanged() end)
	ProtectedCall(function() actwep:Equip(self) end)

	self:ApplyWeaponHoldType(actwep)

	return actwep
end

function ENT:DropWeapon(velocity, justdrop)
	local wep = self:GetActiveWeapon()
	if not IsValid(wep) then return end

	local actwep = self:GetActiveLuaWeapon()

	if not justdrop then
		velocity = velocity or self:GetEyeAngles():Forward() * 200
		local spd = velocity:Length()
		velocity = velocity / spd
		velocity:Mul(math.min(spd, 400))
	end

	self:SetActiveWeapon(NULL)
	self.m_WeaponHoldType = nil

	wep:SetParent()
	wep:RemoveEffects(EF_BONEMERGE)
	wep:RemoveSolidFlags(FSOLID_NOT_SOLID)
	wep:CollisionRulesChanged()
	wep:SetOwner(NULL)
	wep:SetMoveType(MOVETYPE_FLYGRAVITY)

	local SF = wep:GetSolidFlags()
	if not wep:PhysicsInit(SOLID_VPHYSICS) then
		wep:SetSolid(SOLID_BBOX)
	else
		wep:SetMoveType(MOVETYPE_VPHYSICS)
		wep:PhysWake()
	end
	wep:SetSolidFlags(bit.bor(SF, FSOLID_TRIGGER))
	wep:SetTransmitWithParent(false)

	ProtectedCall(function() actwep:OwnerChanged() end)
	ProtectedCall(function() actwep:OnDrop() end)

	if wep != actwep then
		wep:SetClip1(actwep:Clip1())
		wep:SetClip2(actwep:Clip2())
		actwep:DontDeleteOnRemove(wep)
		actwep:Remove()
	end

	ProtectedCall(function() self:OnWeaponDrop(wep) end)

	if not justdrop then
		wep:SetPos(self:GetShootPos())
		wep:SetAngles(self:GetEyeAngles())

		local phys = wep:GetPhysicsObject()
		if IsValid(phys) then
			phys:AddVelocity(velocity)
			phys:AddAngleVelocity(Vector(200, 200, 200))
		else
			wep:SetVelocity(velocity)
		end
	else
		local dir = self:GetAimVector()
		dir.z = 0
		wep:SetPos(self:GetShootPos() + dir * 10)

		local phys = wep:GetPhysicsObject()
		if IsValid(phys) then
			phys:AddVelocity(self.loco:GetVelocity())
		else
			wep:SetVelocity(self.loco:GetVelocity())
		end
	end

	return wep
end

function ENT:ReloadWeaponData()
	self.m_WeaponData = {
		Primary = {BurstBullets = -1, BurstBullet = 0, NextShootTime = 0},
		Secondary = {NextShootTime = 0},
		NextReloadTime = 0,
	}
end

function ENT:CanWeaponPrimaryAttack()
	if not self:HasWeapon() or CurTime() < self.m_WeaponData.Primary.NextShootTime then return false end
	local wep = self:GetActiveLuaWeapon()
	if CurTime() < wep:GetNextPrimaryFire() then return false end
	return true
end

function ENT:WeaponPrimaryAttack()
	if not self:CanWeaponPrimaryAttack() then return end
	local wep = self:GetActiveLuaWeapon()
	local data = self.m_WeaponData.Primary

	self:ApplyWeaponHoldType(wep)

	ProtectedCall(function() wep:NPCShoot_Primary(self:GetShootPos(), self:GetAimVector()) end)
	self:DoRangeGesture()

	if self:ShouldWeaponAttackUseBurst(wep) then
		local bmin, bmax, frate = 1, 1, 1
		if wep.GetNPCBurstSettings then bmin, bmax, frate = wep:GetNPCBurstSettings() end
		local rmin, rmax = 0.33, 0.66
		if wep.GetNPCRestTimes then rmin, rmax = wep:GetNPCRestTimes() end

		if data.BurstBullets == -1 then data.BurstBullets = math.random(bmin, bmax) end
		data.BurstBullet = data.BurstBullet + 1

		if data.BurstBullet >= data.BurstBullets then
			data.BurstBullets = -1
			data.BurstBullet = 0
			data.NextShootTime = math.max(CurTime() + math.Rand(rmin, rmax), data.NextShootTime)
		else
			data.NextShootTime = math.max(CurTime() + frate, data.NextShootTime)
		end
	else
		local bmin, bmax, frate = 1, 1, 1
		if wep.GetNPCBurstSettings then bmin, bmax, frate = wep:GetNPCBurstSettings() end
		data.NextShootTime = math.max(CurTime() + frate, data.NextShootTime)
	end
end

function ENT:CanWeaponSecondaryAttack()
	if not self:HasWeapon() or CurTime() < self.m_WeaponData.Secondary.NextShootTime then return false end
	local wep = self:GetActiveLuaWeapon()
	if CurTime() < wep:GetNextSecondaryFire() then return false end
	return true
end

function ENT:WeaponSecondaryAttack()
	if not self:CanWeaponSecondaryAttack() then return end
	local wep = self:GetActiveLuaWeapon()
	self:ApplyWeaponHoldType(wep)
	ProtectedCall(function() wep:NPCShoot_Secondary(self:GetShootPos(), self:GetAimVector()) end)
	self:DoRangeGesture()
end

function ENT:GetAimVector()
	local dir = self:GetEyeAngles():Forward()
	if self:HasWeapon() then
		local wep = self:GetActiveLuaWeapon()
		local spread = 15
		if wep.GetNPCBulletSpread then spread = wep:GetNPCBulletSpread(self:GetCurrentWeaponProficiency()) end
		local deg = math.sin(math.rad(spread)) / 2
		dir:Add(Vector(math.Rand(-deg, deg), math.Rand(-deg, deg), math.Rand(-deg, deg)))
	end
	return dir
end

function ENT:DoRangeGesture()
	local wep = self:GetActiveLuaWeapon()
	if IsValid(wep) then self:ApplyWeaponHoldType(wep) end

	local act = self:TranslateActivity(self:IsCrouching() and ACT_MP_ATTACK_CROUCH_PRIMARYFIRE or ACT_MP_ATTACK_STAND_PRIMARYFIRE)
	local seq = self:SelectWeightedSequence(act)
	self:DoGesture(act)
	return self:SequenceDuration(seq)
end

function ENT:DoReloadGesture()
	local wep = self:GetActiveLuaWeapon()
	if IsValid(wep) then self:ApplyWeaponHoldType(wep) end

	local act = self:TranslateActivity(self:IsCrouching() and ACT_MP_RELOAD_CROUCH or ACT_MP_RELOAD_STAND)
	local seq = self:SelectWeightedSequence(act)
	self:DoGesture(act)
	return self:SequenceDuration(seq)
end

function ENT:WeaponReload()
	if not self:HasWeapon() then return end
	local wep = self:GetActiveLuaWeapon()
	if wep:Clip1() >= wep:GetMaxClip1() then return end
	if CurTime() < self.m_WeaponData.NextReloadTime then return end
	wep:SetClip1(wep:GetMaxClip1())
	local time = CurTime() + self:DoReloadGesture()
	self.m_WeaponData.Primary.NextShootTime = math.max(time, self.m_WeaponData.Primary.NextShootTime)
	self.m_WeaponData.Secondary.NextShootTime = math.max(time, self.m_WeaponData.Secondary.NextShootTime)
	self.m_WeaponData.NextReloadTime = time
end

function ENT:SetCurrentWeaponProficiency(prof) self.m_WeaponProficiency = prof end
function ENT:GetCurrentWeaponProficiency() return self.m_WeaponProficiency or WEAPON_PROFICIENCY_GOOD end

function ENT:OnWeaponEquip(wep) self:RunTask("OnWeaponEquip", wep) end
function ENT:OnWeaponDrop(wep) self:RunTask("OnWeaponDrop", wep) end

function ENT:CanPickupWeapon(wep)
	return wep:IsWeapon() and IsValid(wep) and (wep:IsScripted() and wep.CanBePickedUpByNPCs and wep:CanBePickedUpByNPCs() or EngineAnalogs[wep:GetClass()]) and not IsValid(wep:GetOwner()) or false
end

function ENT:CanDropWeaponOnDie(wep)
	return not self:HasSpawnFlags(SF_NPC_NO_WEAPON_DROP)
end

--[[------------------------------------
	Burst control hierarchy (highest first):
	1. Task "ShouldWeaponAttackUseBurst"
	2. Weapon: wep.AaronBotUseBurst / wep.UseBurst
	3. Bot: ENT.UseWeaponBurst / SetUseWeaponBurst
	4. Default true
--]]------------------------------------
function ENT:SetUseWeaponBurst(use)
	self.UseWeaponBurst = use and true or false
end

function ENT:GetUseWeaponBurst()
	return self.UseWeaponBurst ~= false
end

function ENT:ShouldWeaponAttackUseBurst(wep)
	wep = wep or self:GetActiveLuaWeapon()

	local task = self:RunTask("ShouldWeaponAttackUseBurst", wep)
	if task ~= nil then return task and true or false end

	if IsValid(wep) then
		if wep.AaronBotUseBurst ~= nil then return wep.AaronBotUseBurst and true or false end
		if wep.UseBurst ~= nil then return wep.UseBurst and true or false end
	end

	return self:GetUseWeaponBurst()
end

function ENT:IsMeleeWeapon(wep)
	wep = wep or self:GetActiveLuaWeapon()
	return IsValid(wep) and wep.GetCapabilities and bit.band(wep:GetCapabilities(), CAP_WEAPON_MELEE_ATTACK1) != 0 or false
end

hook.Add("PlayerCanPickupWeapon", "AaronBot", function(ply, wep)
	if IsValid(wep:GetOwner()) and wep:GetOwner().AaronBot then return false end
	if EngineAnalogsReverse[wep:GetClass()] then return false end
end)
