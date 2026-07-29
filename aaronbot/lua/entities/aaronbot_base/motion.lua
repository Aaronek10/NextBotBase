-- AaronBot Motion (locomotion, path, speed, activity)
-- Full port of original motion.lua will follow; this provides essential methods so the base loads without errors.

function ENT:SetupCollisionBounds()
	local mins, maxs = self.CollisionBounds[1], self.CollisionBounds[2]
	if self:IsCrouching() then
		mins, maxs = self.CrouchCollisionBounds[1], self.CrouchCollisionBounds[2]
	end
	self:SetCollisionBounds(mins, maxs)
end

function ENT:SwitchCrouch(crouch)
	self:SetCrouching(crouch)
	self:SetupCollisionBounds()
end

function ENT:ShouldCrouch()
	return false -- override in tasks/subclasses
end

function ENT:CanStandUp()
	return true
end

function ENT:StuckCheck()
	-- basic stuck detection placeholder
end

function ENT:SetupEyeAngles()
	-- placeholder
end

function ENT:LocomotionUpdate(interval)
	-- placeholder for velocity / step sounds etc.
end

function ENT:PathIsValid()
	return IsValid(self.m_Path) and self.m_Path:IsValid()
end

function ENT:GetPath()
	return self.m_Path
end

function ENT:GetPathPos()
	return self.m_PathPos
end

function ENT:SetupPath(pos)
	self.m_PathPos = pos
	self.m_Path:Compute(self, pos)
end

function ENT:ControlPath(draw)
	if self:PathIsValid() then
		self.m_Path:Update(self)
		if draw and self.DrawPath:GetBool() then
			self.m_Path:Draw()
		end
	end
end

function ENT:Approach(pos)
	self.loco:Approach(pos, 1)
end

function ENT:Jump()
	self.loco:Jump()
end

function ENT:IsUsingLadder()
	return self.m_Ladder ~= nil
end

function ENT:AttachToLadder(data)
	self.m_Ladder = data
end

function ENT:DetachFromLadder()
	self.m_Ladder = nil
end

function ENT:GetHullWidth()
	return 32
end

function ENT:GetHullType()
	return self.m_HullType or HULL_HUMAN
end

function ENT:GetDuckHullType()
	return self.m_DuckHullType or HULL_TINY
end

function ENT:TranslateActivity(act)
	local t = self.IdleActivityTranslations[act]
	if isfunction(t) then return t(self) end
	return t or act
end

function ENT:DoGesture(act)
	-- placeholder
end

function ENT:IsGestureActive()
	return false
end

function ENT:IsPostureActive()
	return false
end

function ENT:SetupGesturePosture()
end

function ENT:SetDesiredEyeAngles(ang)
	self.m_DesiredEyeAngles = ang
end

function ENT:IsControlledByPlayer()
	return IsValid(self:GetControlPlayer())
end

function ENT:ControlPlayerKeyDown(key)
	return false -- full impl in playercontrol
end

function ENT:ControlPlayerKeyPressed(key)
	return false
end

function ENT:PhysicsObjectCollide(data, phys)
end

function ENT:BecomeRagdoll(dmg)
	self:BecomeRagdoll(dmg) -- base_nextbot
end
