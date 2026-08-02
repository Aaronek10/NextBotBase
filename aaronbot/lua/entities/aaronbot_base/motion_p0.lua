-- Motion Type Enums
AARONBOT_MOTIONTYPE_IDLE = 0
AARONBOT_MOTIONTYPE_MOVE = 1
AARONBOT_MOTIONTYPE_RUN = 2
AARONBOT_MOTIONTYPE_WALK = 3
AARONBOT_MOTIONTYPE_CROUCH = 4
AARONBOT_MOTIONTYPE_CROUCHWALK = 5
AARONBOT_MOTIONTYPE_JUMPING = 6
AARONBOT_MOTIONTYPE_LADDER = 7

ENT.MotionTypeActivities = {
	[AARONBOT_MOTIONTYPE_IDLE] = ACT_MP_STAND_IDLE,
	[AARONBOT_MOTIONTYPE_MOVE] = ACT_MP_RUN,
	[AARONBOT_MOTIONTYPE_RUN] = ACT_MP_RUN,
	[AARONBOT_MOTIONTYPE_WALK] = ACT_MP_WALK,
	[AARONBOT_MOTIONTYPE_CROUCH] = ACT_MP_CROUCH_IDLE,
	[AARONBOT_MOTIONTYPE_CROUCHWALK] = ACT_MP_CROUCHWALK,
	[AARONBOT_MOTIONTYPE_JUMPING] = ACT_MP_JUMP,
	[AARONBOT_MOTIONTYPE_LADDER] = ACT_MP_JUMP,
}

GO_NORTH = 0
GO_EAST = 1
GO_SOUTH = 2
GO_WEST = 3
GO_LADDER_UP = 4
GO_LADDER_DOWN = 5
GO_JUMP = 6
GO_ELEVATOR_UP = 7
GO_ELEVATOR_DOWN = 8

ON_GROUND = 0
DROP_DOWN = 1
CLIMB_UP = 2
JUMP_OVER_GAP = 3
LADDER_UP = 4
LADDER_DOWN = 5

Ladders, LaddersUpdate = Ladders or {}, LaddersUpdate
function UpdateLadders()
	if LaddersUpdate and CurTime() - LaddersUpdate < 30 then return end
	Ladders, LaddersUpdate = {}, CurTime()
	local ladders = {}
	for k, v in ipairs(navmesh.GetAllNavAreas()) do
		for _, ladder in ipairs(v:GetLadders()) do
			if not ladders[ladder] then
				ladders[ladder] = true
				Ladders[#Ladders + 1] = ladder
			end
		end
	end
end

function SnapToLadderAxis(ladderBottom, ladderTop, point)
	local ladderDirection = (ladderTop - ladderBottom):GetNormalized()
	local bottomToPoint = point - ladderBottom
	local projected = ladderDirection * bottomToPoint:Dot(ladderDirection)
	return ladderBottom + projected
end

function Dist2D(pos1, pos2)
	local d = pos1 - pos2
	return d:Length2D()
end

function ENT:SetMotionType(type)
	self.m_MotionType = type
end

function ENT:GetMotionType()
	return self.m_MotionType or AARONBOT_MOTIONTYPE_IDLE
end

function ENT:SetupSpeed()
	local speed = 0
	if self:IsCrouching() then
		speed = self:ShouldWalk() and self.WalkSpeed or self.CrouchSpeed
	else
		if self:ShouldRun() then
			speed = self.RunSpeed
		elseif self:ShouldWalk() then
			speed = self.WalkSpeed
		else
			speed = self.MoveSpeed
		end
	end
	speed = self:RunTask("ModifyMovementSpeed", speed) or speed
	self.loco:SetDesiredSpeed(speed)
	self.m_Speed = speed
end

function ENT:GetCurrentSpeed()
	return self.loco:GetVelocity():Length2D()
end

function ENT:GetDesiredSpeed()
	return self.m_Speed or 0
end

function ENT:IsMoving()
	return self:GetCurrentSpeed() > 0.1
end

function ENT:SetupMotionType()
	local moving = self:IsMoving()
	local type = AARONBOT_MOTIONTYPE_IDLE
	if self:IsJumping() then
		type = AARONBOT_MOTIONTYPE_JUMPING
	elseif self:IsUsingLadder() then
		type = AARONBOT_MOTIONTYPE_LADDER
	elseif self:IsCrouching() then
		type = moving and AARONBOT_MOTIONTYPE_CROUCHWALK or AARONBOT_MOTIONTYPE_CROUCH
	elseif moving then
		local speed = self:GetCurrentSpeed()
		if speed > self.MoveSpeed + 1 then
			type = AARONBOT_MOTIONTYPE_RUN
		elseif speed < self.MoveSpeed / 2 + 1 then
			type = AARONBOT_MOTIONTYPE_WALK
		else
			type = AARONBOT_MOTIONTYPE_MOVE
		end
	end
	self:SetMotionType(type)
end

function ENT:SetDesiredEyeAngles(ang)
	self.m_DesiredEyeAngles = ang
end

function ENT:GetDesiredEyeAngles()
	return self.m_DesiredEyeAngles or angle_zero
end

function IsAngleEqual(ang1, ang2)
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
	if not IsAngleEqual(self:GetAngles(), newang) then
		self:SetAngles(newang)
		local phys = self:GetPhysicsObject()
		if phys:IsValid() and not IsAngleEqual(phys:GetAngles(), angle_zero) then phys:SetAngles(angle_zero) end
	end
	self.m_PitchAim = angp
	self:SetPoseParameter("aim_pitch", self.m_PitchAim + punch.p)
	self:SetPoseParameter("aim_yaw", punch.y)
	self:SetEyeTarget(self:GetShootPos() + self:GetEyeAngles():Forward() * 100)
end

function ENT:ViewPunch(ang)
	self:SetViewPunchTime(CurTime())
	self:SetViewPunchAngle(ang)
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

function ENT:SetupActivity()
	local curact = self:GetActivity()
	local act = self:RunTask("GetDesiredActivity")
	if not act then
		act = self.MotionTypeActivities[self:GetMotionType()]
		act = self:TranslateActivity(act)
	end
	if act and curact != act then
		self:StartActivity(act)
	end
end

function ENT:DoGesture(act, speed, wait)
	self.m_DoGesture = {act, speed or 1, wait}
end

function ENT:DoPosture(act, issequence, speed, noautokill)
	local seq = issequence and act or self:SelectWeightedSequence(act)
	self.m_DoPosture = {seq, speed or 1, not noautokill}
	if issequence and isstring(seq) then
		local seqid, len = self:LookupSequence(seq)
		return len
	end
	return self:SequenceDuration(seq)
end

function ENT:StopGesture()
	if self.m_CurGesture then
		self:RemoveGesture(self.m_CurGesture[1])
		self.m_CurGesture = nil
	end
end

function ENT:StopPosture()
	if self.m_CurPosture then
		self.m_CurPosture = nil
		self:ResetSequenceInfo()
		self:StartActivity(self:GetActivity())
	end
end

function ENT:IsGestureActive(wait)
	return self.m_CurGesture and CurTime() < self.m_CurGesture[2] and (not wait or self.m_CurGesture[3]) or false
end

function ENT:IsPostureActive()
	return self.m_CurPosture and (not self.m_CurPosture[2] or CurTime() < self.m_CurPosture[1]) or false
end

function ENT:SetupGesturePosture()
	if self.m_DoGesture then
		local act = self.m_DoGesture[1]
		local spd = self.m_DoGesture[2]
		local wait = self.m_DoGesture[3]
		self.m_DoGesture = nil
		local clayer = self.m_CurGesture and self.m_CurGesture[4]
		self:StopGesture()
		local layer = self:AddGesture(act)
		self:SetLayerPlaybackRate(layer, spd)
		self:SetLayerBlendIn(layer, 0.2)
		self:SetLayerBlendOut(layer, 0.2)
		if clayer and self:IsValidLayer(clayer) and self:GetLayerSequence(clayer) == self:GetLayerSequence(layer) then
			self:SetLayerWeight(clayer, 0)
		end
		self.m_CurGesture = {act, CurTime() + self:GetLayerDuration(layer), wait, layer}
	end
	if self.m_DoPosture then
		local seq = self.m_DoPosture[1]
		local spd = self.m_DoPosture[2]
		local autokill = self.m_DoPosture[3]
		self.m_DoPosture = nil
		self:StopPosture()
		local len = self:SetSequence(seq)
		self:ResetSequenceInfo()
		self:SetCycle(0)
		self:SetPlaybackRate(spd)
		self.m_CurPosture = {CurTime() + len / spd, autokill}
	end
	if self.m_CurPosture and self.m_CurPosture[2] and CurTime() > self.m_CurPosture[1] then
		self:StopPosture()
	end
end

function ENT:BodyUpdate()
	if not self:IsPostureActive() then
		self:SetupActivity()
	end
	if self:IsMoving() then
		self:BodyMoveXY()
	else
		self:FrameAdvance()
	end
	self:RunTask("BodyUpdate")
end

function ENT:LocomotionUpdate(interval)
	self:UpdatePhysicsObject()
	if self.m_Physguned then
		self.loco:SetVelocity(vector_origin)
	end
	local ladder = self.m_Ladder
	if not ladder then
		if self.CanUseLadder then
			local dir = self.loco:GetVelocity()
			local len = dir:Length2D()
			if len >= 1 then
				UpdateLadders()
				if #Ladders > 0 then
					local curpos = self:GetPos()
					local step = self.StepHeight
					local width = self:GetHullWidth() / 2
					dir:Normalize()
					for l = 1, #Ladders do
						local lad = Ladders[l]
						local dot = dir:Dot(lad:GetNormal())
						if dot < -0.5 and curpos.z > lad:GetBottom().z - step and curpos.z < lad:GetTop().z - step and util.DistanceToLine(lad:GetBottom(), lad:GetTop(), curpos) < lad:GetWidth() + width then
							self:AttachToLadder(lad)
							break
						end
					end
				end
			end
		end
	else
		local pos = self:GetPos()
		if not self.m_LadderJustAttached then
			local axisPos = SnapToLadderAxis(ladder.Bottom, ladder.Top, pos)
			local dist2d = Dist2D(pos, axisPos)
			local offAxis = dist2d > self:GetHullWidth() * 0.75
			local below = pos.z < ladder.Bottom.z - 8
			local above = pos.z > ladder.Top.z + 8
			if offAxis or below or above then
				self:DetachFromLadder(nil, "off_axis_or_ends")
			else
				if dist2d > 4 then
					local snap = axisPos
					snap.z = pos.z
					self:SetPos(snap)
				end
				local goal = self.m_LadderApproach
				if goal then
					local climbDir = (goal - pos):GetNormalized()
					local speed = self.LadderClimbSpeed or 200
					self.loco:SetVelocity(climbDir * speed)
				else
					self.loco:SetVelocity(vector_origin)
				end
				self.loco:SetStepHeight(1)
			end
		end
		self.m_LadderApproach = nil
		self.m_LadderJustAttached = nil
	end
	self:SetupSpeed()
	self:SetupMotionType()
	self:ProcessFootsteps()
end
