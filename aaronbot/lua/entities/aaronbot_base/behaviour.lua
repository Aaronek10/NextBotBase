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

-- Player control removed (stubs kept only if anything still checks them)
function ENT:IsControlledByPlayer()
	return false
end

function ENT:GetControlPlayer()
	return NULL
end

function ENT:ControlPlayerKeyDown(key)
	return false
end

function ENT:ControlPlayerKeyPressed(key)
	return false
end

function ENT:StartControlByPlayer(ply)
end

function ENT:StopControlByPlayer()
end

--[[------------------------------------
	Motion overrides (loaded after motion.lua via init include order).
	No player-control branches; IdleActivityTranslations for animations.
--]]------------------------------------
local function AngleEqual(ang1, ang2)
	return math.abs(math.AngleDifference(ang1.p, ang2.p)) < 0.01
		and math.abs(math.AngleDifference(ang1.y, ang2.y)) < 0.01
		and math.abs(math.AngleDifference(ang1.r, ang2.r)) < 0.01
end

function ENT:SetupEyeAngles()
	local angp = self.m_PitchAim
	local angy = self:GetAngles().y
	local desired = self:GetDesiredEyeAngles()
	local punch = self:GetViewPunchAngles()
	local diffp = math.AngleDifference(desired.p, angp)
	local diffy = math.AngleDifference(desired.y, angy)
	local max = self.BehaveInterval * self.AimSpeed
	diffp = diffp < 0 and math.max(-max, diffp) or math.min(max, diffp)
	diffy = diffy < 0 and math.max(-max, diffy) or math.min(max, diffy)
	angp = angp + diffp
	angy = angy + diffy
	local newang = Angle(0, angy, 0)
	if not AngleEqual(self:GetAngles(), newang) then
		self:SetAngles(newang)
		local phys = self:GetPhysicsObject()
		if phys:IsValid() and not AngleEqual(phys:GetAngles(), angle_zero) then phys:SetAngles(angle_zero) end
	end
	self.m_PitchAim = angp
	self:SetPoseParameter("aim_pitch", self.m_PitchAim + punch.p)
	self:SetPoseParameter("aim_yaw", punch.y)
	self:SetEyeTarget(self:GetShootPos() + self:GetEyeAngles():Forward() * 100)
end

function ENT:TranslateActivity(act)
	local task = self:RunTask("TranslateActivity", act)
	if task then return task end
	if self:HasWeapon() then
		self.m_PassIsNPCCheck = false
		local newact
		ProtectedCall(function() newact = self:GetActiveLuaWeapon():TranslateActivity(act) end)
		self.m_PassIsNPCCheck = true
		if newact then return newact end
	end
	local t = self.IdleActivityTranslations and self.IdleActivityTranslations[act]
	if isfunction(t) then return t(self) end
	if t then return t end
	return self.IdleActivity or ACT_HL2MP_IDLE
end

function ENT:ShouldRun()
	return self:RunTask("ShouldRun") or false
end

function ENT:ShouldWalk()
	return self:RunTask("ShouldWalk") or false
end

function ENT:ShouldCrouch()
	if not self.CanCrouch then return false end
	if self.m_Jumping then return true end
	if not self:UsingNodeGraph() then
		if self:PathIsValid() and not self:IsMoving() then
			local prev = self:GetPath():PriorSegment()
			if prev and prev.area:HasAttributes(NAV_MESH_CROUCH) then return true end
		elseif IsValid(self:GetCurrentNavArea()) and self:GetCurrentNavArea():HasAttributes(NAV_MESH_CROUCH) then
			return true
		end
	else
		if self:PathIsValid() and self:GetPath():GetCurrentGoal() and self:GetPath():GetCurrentGoal().type == (AaronBotNodeGraph and AaronBotNodeGraph.PATH_SEGMENT_MOVETYPE_CROUCHING or 1) then
			return true
		end
	end
	return self:RunTask("ShouldCrouch") or false
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
