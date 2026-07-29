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

		local ply = self:GetControlPlayer()
		if IsValid(ply) then
			if self:HasWeapon() then
				local wep = self:GetActiveWeapon()
				local clip1, clip2, maxclip1, maxclip2 = wep:Clip1(), wep:Clip2(), wep:GetMaxClip1(), wep:GetMaxClip2()

				if self:GetWeaponClip1() != clip1 then self:SetWeaponClip1(clip1) end
				if self:GetWeaponClip2() != clip2 then self:SetWeaponClip2(clip2) end
				if self:GetWeaponMaxClip1() != maxclip1 then self:SetWeaponMaxClip1(maxclip1) end
				if self:GetWeaponMaxClip2() != maxclip2 then self:SetWeaponMaxClip2(maxclip2) end
			end

			self:BehaviourPlayerControlThink(ply)
			self:RunTask("PlayerControlUpdate", interval, ply)
			self.m_ControlPlayerOldButtons = self.m_ControlPlayerButtons
		else
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

	return GetConVar("ai_disabled"):GetBool() and not self:IsControlledByPlayer() or self:RunTask("DisableBehaviour")
end

function ENT:BehaviourThink()
	-- Override in subclasses / use tasks for real AI.
	-- Default: idle (no player-control host behaviour).
end

function ENT:BehaviourPlayerControlThink(ply)
	local eyeang = ply:EyeAngles()
	local forward, right = eyeang:Forward(), eyeang:Right()
	local f = self:ControlPlayerKeyDown(IN_FORWARD) and 1 or self:ControlPlayerKeyDown(IN_BACK) and -1 or 0
	local r = self:ControlPlayerKeyDown(IN_MOVELEFT) and 1 or self:ControlPlayerKeyDown(IN_MOVERIGHT) and -1 or 0

	if f != 0 or r != 0 then
		local eyeang = ply:EyeAngles()
		if not self:IsUsingLadder() then eyeang.p = 0 end
		eyeang.r = 0
		local movedir = eyeang:Forward() * f - eyeang:Right() * r
		self:Approach(self:GetPos() + movedir * 100)
	end

	if self:ControlPlayerKeyPressed(IN_JUMP) then
		self:Jump()
	end

	if self:HasWeapon() then
		local wep = self:GetActiveLuaWeapon()

		if self[wep.Primary.Automatic and "ControlPlayerKeyDown" or "ControlPlayerKeyPressed"](self, IN_ATTACK) then
			if wep:Clip1() <= 0 and wep:GetMaxClip1() > 0 then
				self:WeaponReload()
			else
				self:WeaponPrimaryAttack()
			end
		end

		if self[wep.Secondary.Automatic and "ControlPlayerKeyDown" or "ControlPlayerKeyPressed"](self, IN_ATTACK2) then
			self:WeaponSecondaryAttack()
		end

		if self:ControlPlayerKeyPressed(IN_RELOAD) then
			self:WeaponReload()
		end
	end

	if self:ControlPlayerKeyPressed(IN_USE) then
		local pos = self:GetShootPos()
		local tr = util.TraceLine({start = pos, endpos = pos + forward * 72, filter = self})

		if tr.Hit then
			if self:CanPickupWeapon(tr.Entity) and not self:HasWeapon() then
				self:SetupWeapon(tr.Entity)
			else
				tr.Entity:Input("Use", self, self)
			end
		end
	end
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
