function ENT:BehaveStart()
	self:SetupCollisionBounds()

	self:SetupTaskList(self.m_TaskList)
	self:SetupTasks()

	self.BehaviourThread = coroutine.create(function()
		self:BehaviourCoroutine()
	end)
end

function ENT:BehaveUpdate(interval)
	self.BehaveInterval = interval

	self:StuckCheck()

	local disable = self:DisableBehaviour()

	if not disable then
		local crouch = self:ShouldCrouch()
		if crouch != self:IsCrouching() and (crouch or self:CanStandUp()) then
			self:SwitchCrouch(crouch)
		end
	end

	if not disable then
		self:SetupEyeAngles()
		self:UpdateEnemies()

		if self.BehaviourThread then
			if coroutine.status(self.BehaviourThread) == "dead" then
				self.BehaviourThread = nil
				ErrorNoHalt("NEXTBOT:BehaviourCoroutine() has been finished!\n")
			else
				assert(coroutine.resume(self.BehaviourThread))
			end
		end

		self:BehaviourThink()
		self:RunTask("BehaveUpdate", interval)
	end

	self:SetupGesturePosture()
	self:LocomotionUpdate(interval)
	self.m_FallSpeed = -self.loco:GetVelocity().z
end

function ENT:BehaviourCoroutine()
	while true do
		coroutine.yield()
	end
end

function ENT:DisableBehaviour()
	if self:IsPostureActive() or self.m_DoPosture or self:IsGestureActive(true) or self.m_DoGesture and self.m_DoGesture[3] then
		return true
	end

	return GetConVar("ai_disabled"):GetBool() or self:RunTask("DisableBehaviour")
end

function ENT:BehaviourThink()
	-- Override in subclasses / use tasks for real AI.
	-- Default: idle.
end

function ENT:CapabilitiesAdd(cap)
	self.m_Capabilities = bit.bor(self.m_Capabilities, cap)
end

function ENT:CapabilitiesClear()
	self.m_Capabilities = 0
end

function ENT:CapabilitiesGet()
	return bit.bor(self.m_Capabilities, self:HasWeapon() and self:GetActiveLuaWeapon():GetCapabilities() or 0)
end

function ENT:CapabilitiesRemove(cap)
	self.m_Capabilities = bit.bxor(bit.bor(self.m_Capabilities, cap), cap)
end
