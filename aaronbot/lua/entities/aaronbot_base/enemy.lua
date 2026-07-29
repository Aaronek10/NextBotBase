-- AaronBot Enemy / Relationships

function ENT:UpdateEnemies()
	-- placeholder - full memory + LOS checks next
end

function ENT:SetEntityRelationship(ent, disposition, priority)
	self.m_EntityRelationships[ent] = {disposition = disposition or D_NU, priority = priority or 0}
end

function ENT:SetClassRelationship(class, disposition, priority)
	self.m_ClassRelationships[class] = {disposition = disposition or D_NU, priority = priority or 0}
end

function ENT:GetRelationship(ent)
	if not IsValid(ent) then return D_NU end
	local r = self.m_EntityRelationships[ent]
	if r then return r.disposition end
	r = self.m_ClassRelationships[ent:GetClass()]
	if r then return r.disposition end
	return D_NU
end

function ENT:AddEntityRelationship(target, disposition, priority)
	self:SetEntityRelationship(target, disposition, priority)
end
