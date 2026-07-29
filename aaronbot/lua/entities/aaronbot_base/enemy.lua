local INT_MIN = -2147483648
local DEF_RELATIONSHIP_PRIORITY = INT_MIN

function ENT:SetEnemy(enemy)
	self.m_Enemy = enemy
end

function ENT:GetEnemy()
	return self.m_Enemy or NULL
end

function ENT:SetClassRelationship(class, d, priority)
	self.m_ClassRelationships[class] = {d, priority or DEF_RELATIONSHIP_PRIORITY}
end

function ENT:SetEntityRelationship(ent, d, priority)
	self.m_EntityRelationships[ent] = {d, priority or DEF_RELATIONSHIP_PRIORITY}
end

function ENT:GetRelationship(ent)
	local d, priority

	local entr = self.m_EntityRelationships[ent]
	if entr and (not priority or entr[2] > priority) then
		d, priority = entr[1], entr[2]
	end

	local classr = self.m_ClassRelationships[ent:GetClass()]
	if classr and (not priority or classr[2] > priority) then
		d, priority = classr[1], classr[2]
	end

	return d or D_NU, priority or DEF_RELATIONSHIP_PRIORITY
end

function ENT:EntShootPos(ent, random)
	local hitboxes = {}
	local sets = ent:GetHitboxSetCount()

	if sets then
		for i = 0, sets - 1 do
			for j = 0, ent:GetHitBoxCount(i) - 1 do
				local group = ent:GetHitBoxHitGroup(j, i)
				hitboxes[group] = hitboxes[group] or {}
				hitboxes[group][#hitboxes[group] + 1] = {ent:GetHitBoxBone(j, i), ent:GetHitBoxBounds(j, i)}
			end
		end

		local data

		if hitboxes[HITGROUP_HEAD] and not self:IsMeleeWeapon() then
			data = hitboxes[HITGROUP_HEAD][random and math.random(#hitboxes[HITGROUP_HEAD]) or 1]
		elseif hitboxes[HITGROUP_CHEST] then
			data = hitboxes[HITGROUP_CHEST][random and math.random(#hitboxes[HITGROUP_CHEST]) or 1]
		elseif hitboxes[HITGROUP_GENERIC] then
			data = hitboxes[HITGROUP_GENERIC][random and math.random(#hitboxes[HITGROUP_GENERIC]) or 1]
		end

		if data then
			local bonem = ent:GetBoneMatrix(data[1])
			local center = data[2] + (data[3] - data[2]) / 2
			local pos = LocalToWorld(center, angle_zero, bonem:GetTranslation(), bonem:GetAngles())
			return pos
		end
	end

	return ent:EyePos()
end

function ENT:CanSeePosition(pos)
	local memory = self.m_EnemiesMemory[pos]
	if memory and memory.lastvisupdate == CurTime() then
		return memory.visible
	end

	local p = isentity(pos) and self:EntShootPos(pos) or pos
	local tr = util.TraceLine({start = self:GetShootPos(), endpos = p, mask = self.LineOfSightMask, filter = self})
	local visible = not tr.Hit or isentity(pos) and tr.Entity == pos

	if memory then
		memory.lastvisupdate = CurTime()
		memory.visible = visible
	end

	return visible
end

function ENT:UpdateEnemyMemory(enemy, pos, visible)
	local memory = self.m_EnemiesMemory[enemy]
	if not memory then
		memory = {}
		self.m_EnemiesMemory[enemy] = memory
	end

	if visible == nil then
		visible = self:CanSeePosition(enemy)
	end

	memory.lastupdate = CurTime()
	memory.pos = pos
	memory.visible = visible

	if visible then
		memory.lastvisupdate = CurTime()
	end
end

function ENT:ClearEnemyMemory(enemy)
	enemy = enemy or self:GetEnemy()
	self.m_EnemiesMemory[enemy] = nil

	if self:GetEnemy() == enemy then
		self:SetEnemy(NULL)
	end
end

function ENT:FindEnemies()
	local ShouldBeEnemy = self.ShouldBeEnemy
	local CanSeePosition = self.CanSeePosition
	local UpdateEnemyMemory = self.UpdateEnemyMemory
	local EntShootPos = self.EntShootPos
	local ents = ents.FindInSphere(self:GetPos(), self.MaxSeeEnemyDistance)

	for i = 1, #ents do
		local ent = ents[i]
		if ent == self or not ShouldBeEnemy(self, ent) or not CanSeePosition(self, ent) then continue end
		UpdateEnemyMemory(self, ent, EntShootPos(self, ent), true)
	end
end

function ENT:GetKnownEnemies()
	local t = {}
	for k, v in pairs(self.m_EnemiesMemory) do
		if IsValid(k) and self:ShouldBeEnemy(k) then
			table.insert(t, k)
		end
	end
	return t
end

function ENT:GetLastEnemyPosition(enemy)
	return self.m_EnemiesMemory[enemy] and self.m_EnemiesMemory[enemy].pos
end

function ENT:HaveEnemy()
	local enemy = self:GetEnemy()
	return IsValid(enemy) and self:ShouldBeEnemy(enemy)
end

function ENT:UpdateEnemies()
	for k, v in pairs(self.m_EnemiesMemory) do
		if not IsValid(k) or CurTime() - v.lastupdate >= self.ForgetEnemyTime or not self:ShouldBeEnemy(k) then
			self:ClearEnemyMemory(k)
		end
	end
end

function ENT:ShouldBeEnemy(ent)
	if ent:IsFlagSet(FL_NOTARGET) or not ent:IsPlayer() and not ent:IsNPC() and not ent:IsFlagSet(FL_OBJECT) then return false end
	if ent:IsPlayer() and GetConVar("ai_ignoreplayers"):GetBool() then return false end
	if not ent.AaronBot and ent:IsNPC() and (ent:GetNPCState() == NPC_STATE_DEAD or ent:GetClass() == "npc_barnacle" and ent:GetInternalVariable("m_takedamage") == 0 or (ent:GetClass() == "monster_turret" or ent:GetClass() == "monster_miniturret") and ent:Health() <= 0) then return false end
	if (ent.AaronBot or not ent:IsNPC()) and ent:Health() <= 0 then return false end
	if self:GetRelationship(ent) != D_HT then return false end
	if self:GetRangeSquaredTo(ent) > self.MaxSeeEnemyDistance ^ 2 then return false end
	return true
end

function ENT:FindPriorityEnemy()
	local notsee = {}
	local enemy, range, priority
	local byrange = false

	for k, v in pairs(self.m_EnemiesMemory) do
		if not IsValid(k) or not self:ShouldBeEnemy(k) then continue end

		if not self:CanSeePosition(k) then
			notsee[#notsee + 1] = k
			continue
		end

		local rang = self:GetRangeSquaredTo(k)
		local d, pr = self:GetRelationship(k)

		if not byrange and rang <= self.CloseEnemyDistance ^ 2 then
			byrange = true
		end

		if not enemy or Either(byrange, rang < range, Either(pr == priority, rang < range, pr > priority)) then
			enemy, range, priority = k, rang, pr
		end
	end

	if not enemy then
		for k, v in ipairs(notsee) do
			local rang = self:GetRangeSquaredTo(self:GetLastEnemyPosition(v))
			if not enemy or rang < range then
				enemy, range = v, rang
			end
		end
	end

	return enemy or NULL
end
