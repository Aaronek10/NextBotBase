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
	return self.m_CurPosture and (not self.m_CurPosture[1] or CurTime() < self.m_CurPosture[1]) or false
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
		self:SetSequence(seq)
		self:ResetSequenceInfo()
		self:SetCycle(0)
		self:SetPlaybackRate(spd)
		self.m_CurPosture = {CurTime() + self:GetSequenceDuration(seq) / spd, autokill}
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
			end
		end
		self.m_LadderApproach = nil
		self.m_LadderJustAttached = nil
	end
	self:SetupSpeed()
	self:SetupMotionType()
	self:ProcessFootsteps()
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

function ENT:CanStandUp()
	if not self:IsCrouching() then return true end
	local pos = self:GetPos()
	local bounds = self.CollisionBounds
	return not util.TraceHull({start = pos, endpos = pos, mask = self:GetSolidMask(), collisiongroup = self:GetCollisionGroup(), filter = self, mins = bounds[1], maxs = bounds[2]}).Hit
end

function ENT:SetupCollisionBounds()
	local data = self:IsCrouching() and self.CrouchCollisionBounds or self.CollisionBounds
	self:SetCollisionBounds(data[1], data[2])
	if self:PhysicsInitShadow(false, false) then
		self:GetPhysicsObject():SetMass(85)
	end
end

function ENT:GetHullWidth(average)
	local mins, maxs = self:GetCollisionBounds()
	return average and math.sqrt((maxs.x - mins.x) ^ 2 + (maxs.y - mins.y) ^ 2) or maxs.x - mins.x
end

function ENT:UpdatePhysicsObject()
	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		if not IsAngleEqual(phys:GetAngles(), angle_zero) then phys:SetAngles(angle_zero) end
		local pos = self:GetPos()
		phys:UpdateShadow(pos, angle_zero, self.BehaveInterval)
		if phys:GetPos() != pos then phys:SetPos(pos) end
	end
end

function ENT:PhysicsObjectCollide(data)
end

function ENT:OnContact(ent)
	local trace = self:GetTouchTrace()
	if trace.Hit then self:OnTouch(ent, trace) end
end

function ENT:OnTouch(ent, trace)
end

function ENT:UpdateGravity()
	local gravity = self.DefaultGravity
	if self.m_Physguned or self.m_Ladder then gravity = 0 end
	self.loco:SetGravity(gravity)
end

function ENT:SwitchCrouch(crouch)
	self:SetCrouching(crouch)
	self:SetupCollisionBounds()
end

function ENT:GetCurrentNavArea()
	return self.m_NavArea
end

function ENT:GetPath()
	return self.m_Path
end

function ENT:PathIsValid()
	return self:GetPath():IsValid()
end

function ENT:NavMeshPathCostGenerator(path, area, from, ladder, elevator, len)
	if not IsValid(from) then return 0 end
	if not self.loco:IsAreaTraversable(area) then return -1 end
	if not self.CanCrouch and area:HasAttributes(NAV_MESH_CROUCH) then return -1 end
	if not self.CanUseLadder and ladder then return -1 end
	local dist = 0
	if IsValid(ladder) then
		dist = ladder:GetLength()
	elseif len > 0 then
		dist = len
	else
		dist = area:GetCenter():Distance(from:GetCenter())
	end
	if area:HasAttributes(NAV_MESH_JUMP) then dist = dist * 5 end
	if area:HasAttributes(NAV_MESH_AVOID) then dist = dist * 10 end
	local cost = dist + from:GetCostSoFar()
	local deltaZ = ladder and 0 or from:ComputeAdjacentConnectionHeightChange(area)
	if deltaZ >= self.loco:GetStepHeight() then
		if deltaZ >= self.loco:GetMaxJumpHeight() then return -1 end
		cost = cost + dist * 5
	elseif deltaZ < -self.loco:GetDeathDropHeight() then
		return -1
	end
	return cost
end

function ENT:SetupPath(pos, options)
	self:GetPath():Invalidate()
	options = options or {}
	options.mindist = options.mindist or self.PathMinLookAheadDistance
	options.tolerance = options.tolerance or self.PathGoalTolerance
	options.recompute = options.recompute or self.PathRecompute
	if not options.generator and not self:UsingNodeGraph() then
		options.generator = function(area, from, ladder, elevator, len)
			return self:NavMeshPathCostGenerator(self:GetPath(), area, from, ladder, elevator, len)
		end
	end
	local path = self:UsingNodeGraph() and self:NodeGraphPath() or Path("Follow")
	self.m_Path = path
	path:SetMinLookAheadDistance(options.mindist)
	path:SetGoalTolerance(options.tolerance)
	self.m_PathOptions = options
	self.m_PathPos = pos
	if not self:ComputePath(pos, options.generator) then
		path:Invalidate()
		return false
	end
	return path
end

function ENT:ComputePath(pos, generator)
	local path = self:GetPath()
	if path:Compute(self, pos, generator) then
		local ang = self:GetAngles()
		path:Update(self)
		self:SetAngles(ang)
	end
	return path:IsValid()
end

function ENT:ControlPath(lookatgoal)
	if not self:PathIsValid() then return false end
	local path = self:GetPath()
	local pos = self:GetPathPos()
	local options = self.m_PathOptions or {}
	if not self.m_Ladder then
		local range = self:GetRangeSquaredTo(pos)
		if range < (options.tolerance or self.PathGoalTolerance) ^ 2 or range < self.PathGoalToleranceFinal ^ 2 then
			path:Invalidate()
			return true
		end
		local recompute = options.recompute or self.PathRecompute or 5
		local age = path:GetAge()
		local needRecompute = age > recompute
		if not needRecompute and age > 0.35 and self.loco:IsOnGround() then
			local seg = path:GetCurrentGoal()
			if seg and seg.pos and self:GetRangeSquaredTo(seg.pos) > (200 ^ 2) then
				needRecompute = true
			end
		end
		if needRecompute and self.loco:IsOnGround() then
			path:ResetAge()
			if not self:ComputePath(pos, options.generator) then return false end
		end
	end
	if self:MoveAlongPath(lookatgoal) then return true end
	return false
end

function ENT:UpdatePathGoal(pos, force)
	if not pos then return false end
	self.m_PathPos = pos
	if force or not self:PathIsValid() then
		return self:SetupPath(pos, self.m_PathOptions) and true or false
	end
	local path = self:GetPath()
	if path and path.ResetAge then path:ResetAge() end
	return true
end

function ENT:OnNavAreaChanged(old, new)
	self.m_NavArea = new
	if new:HasAttributes(NAV_MESH_STOP) and self.loco:IsOnGround() then
		local vel = self.loco:GetVelocity()
		vel.x = 0
		vel.y = 0
		self.loco:SetVelocity(vel)
	end
end

function ENT:Approach(pos)
	if self.m_Ladder then
		local curpos = self:GetPos()
		local axisPos = SnapToLadderAxis(self.m_Ladder.Bottom, self.m_Ladder.Top, curpos)
		local target = SnapToLadderAxis(self.m_Ladder.Bottom, self.m_Ladder.Top, pos)
		local climb = target
		climb.z = pos.z
		if Dist2D(curpos, axisPos) > self:GetHullWidth() * 0.75 then
			climb.x = axisPos.x
			climb.y = axisPos.y
		end
		self.m_LadderApproach = climb
	else
		if not self:UsingNodeGraph() then
			UpdateLadders()
			local curpos = self:GetPos()
			local width = self:GetHullWidth() / 2
			local dir = pos - curpos
			dir:Normalize()
			for l = 1, #Ladders do
				local ladder = Ladders[l]
				local dot = dir:Dot(ladder:GetNormal())
				if dot < 0 and curpos.z > ladder:GetBottom().z + 1 and curpos.z < ladder:GetTop().z - 1 and util.DistanceToLine(ladder:GetBottom(), ladder:GetTop(), curpos) < ladder:GetWidth() + width then
					self:AttachToLadder(ladder)
					return
				end
			end
		end
		if self.loco:IsOnGround() then
			self.loco:Approach(pos, 1)
		elseif not self.m_JumpingToPos then
			local dt = self.BehaveInterval
			local maxspd = math.min(50, self.m_Speed or 0)
			local dir = pos - self:GetPos()
			dir.z = 0
			local ang = dir:Angle()
			local vel = self.loco:GetVelocity()
			vel = WorldToLocal(vel, angle_zero, vector_origin, ang)
			if vel.x < maxspd then
				if vel.x < 0 then vel.x = vel.x + self.loco:GetDeceleration() * dt
				else vel.x = vel.x + self.loco:GetAcceleration() * dt end
				vel.x = math.min(vel.x, maxspd)
			end
			local decy = self.loco:GetDeceleration() * dt
			if math.abs(vel.y) > decy then
				vel.y = vel.y > 0 and vel.y - decy or vel.y + decy
			else
				vel.y = 0
			end
			vel = LocalToWorld(vel, angle_zero, vector_origin, ang)
			self.loco:SetVelocity(vel)
		end
	end
end

function ENT:AttachToLadder(ladder)
	if not ladder then return self:DetachFromLadder() end
	local navladder = type(ladder) == "CNavLadder"
	local bottom = navladder and ladder:GetBottom() or ladder.bottom
	local top = navladder and ladder:GetTop() or ladder.top
	local normal = navladder and ladder:GetNormal() or ladder.normal
	local width = self:GetHullWidth(true)
	local offset = normal * (width * 0.5)
	self.m_Ladder = {
		Bottom = bottom + offset,
		Top = top + offset,
		Normal = normal,
		Source = ladder,
	}
	self.m_LadderApproach = nil
	self.m_LadderJustAttached = true
	self.m_Jumping = false
	self.m_JumpingToPos = false

	local pos = self:GetPos()
	local mount = SnapToLadderAxis(self.m_Ladder.Bottom, self.m_Ladder.Top, pos)
	mount.z = math.Clamp(pos.z, self.m_Ladder.Bottom.z + self.StepHeight, self.m_Ladder.Top.z - self.StepHeight)

	self.loco:SetStepHeight(1)
	self:UpdateGravity()
	if self.loco:IsOnGround() then self.loco:Jump() end
	self:SetPos(mount)
	self.loco:SetVelocity(vector_origin)
	self:RunTask("OnLadderEnter", ladder)
end

function ENT:DetachFromLadder(exitPos, reason)
	if not self.m_Ladder then return end

	local ladder = self.m_Ladder
	self.m_Ladder = nil
	self.m_LadderApproach = nil
	self.m_LadderJustAttached = nil
	self.loco:SetStepHeight(self.StepHeight)
	self:UpdateGravity()

	local pos = self:GetPos()
	local dest = exitPos
	if not isvector(dest) then
		if math.abs(pos.z - ladder.Top.z) < math.abs(pos.z - ladder.Bottom.z) then
			dest = ladder.Top + ladder.Normal * 24
			dest.z = ladder.Top.z + 8
		else
			dest = ladder.Bottom + ladder.Normal * 24
			dest.z = ladder.Bottom.z + 4
		end
	end

	if self:PathIsValid() and not self:UsingNodeGraph() then
		local goal = self:GetPath():GetCurrentGoal()
		if goal and goal.ladder then
			self:GetPath():Update(self)
		end
	end

	local away = (dest - pos)
	if away:LengthSqr() < 1 then
		away = ladder.Normal
	else
		away:Normalize()
	end
	self.loco:SetVelocity(away * 120 + Vector(0, 0, 40))
	self:RunTask("OnLadderExit", reason)
end

function ENT:IsUsingLadder()
	return self.m_Ladder and true or false
end

function ENT:HandlePathRemovedWhileOnLadder()
	if not self.m_Ladder then return end
	if self:PathIsValid() then return end
	self:DetachFromLadder(self:GetPos(), "path_removed")
end

function ENT:GetPathPos()
	return self.m_PathPos
end

function ENT:MoveAlongPath(lookatgoal)
	local path = self:GetPath()
	local segment = path:GetCurrentGoal()
	if not segment then return false end
	if lookatgoal then
		local ang = (segment.pos - self:GetShootPos()):Angle()
		ang.p = 0
		self:SetDesiredEyeAngles(ang)
	end
	local pos = self:GetPos()
	local dontupdate = false
	if not self:UsingNodeGraph() then
		if segment.ladder and (segment.how == GO_LADDER_UP or segment.how == GO_LADDER_DOWN) then
			local goingUp = segment.how == GO_LADDER_UP
			local ladderData = self.m_Ladder
			if ladderData then
				dontupdate = true
				local targetZ = goingUp and ladderData.Top.z or ladderData.Bottom.z
				local climbTarget = SnapToLadderAxis(ladderData.Bottom, ladderData.Top, pos)
				climbTarget.z = targetZ + (goingUp and 8 or -4)
				self:SetDesiredEyeAngles((goingUp and (ladderData.Top - ladderData.Bottom) or (ladderData.Bottom - ladderData.Top)):Angle())

				if goingUp and pos.z >= ladderData.Top.z - 20 then
					local nextSeg = path:NextSegment()
					local exitPos = nextSeg and nextSeg.pos or (ladderData.Top + ladderData.Normal * 28)
					self:DetachFromLadder(exitPos, "reached_top")
					dontupdate = false
				elseif not goingUp and pos.z <= ladderData.Bottom.z + 20 then
					local nextSeg = path:NextSegment()
					local exitPos = nextSeg and nextSeg.pos or (ladderData.Bottom + ladderData.Normal * 28)
					self:DetachFromLadder(exitPos, "reached_bottom")
					dontupdate = false
				end
			else
				local ladderstart = goingUp and segment.ladder:GetBottom() or segment.ladder:GetTop()
				local ladderend = goingUp and segment.ladder:GetTop() or segment.ladder:GetBottom()
				local nearend = math.abs(pos.z - ladderend.z) < math.abs(pos.z - ladderstart.z)
				local mountPos = ladderstart + segment.ladder:GetNormal() * self:GetHullWidth(true) / 2
				if not nearend then
					local range = (mountPos - pos):Length2D()
					if range < 55 + self.loco:GetDesiredSpeed() then
						dontupdate = true
						if range < 12 then
							self:AttachToLadder(segment.ladder)
							self:Approach(ladderend)
						else
							self:Approach(mountPos)
						end
					else
						self:Approach(mountPos)
					end
				else
					local nextSeg = path:NextSegment()
					self:Approach(nextSeg and nextSeg.pos or mountPos)
				end
			end
		else
			if self.m_Ladder then self:DetachFromLadder() end
			local prev = path:PriorSegment()
			if (segment.how == GO_JUMP or segment.how <= GO_WEST and prev and prev.area:HasAttributes(NAV_MESH_JUMP)) and self.loco:IsOnGround() and self.loco:GetJumpHeight() > 0 then
				local dojump = true
				local deltaz = segment.pos.z - pos.z
				if deltaz <= 0 and (segment.pos - pos):Length2DSqr() < path:GetGoalTolerance() ^ 2 then dojump = false
				elseif deltaz < self.loco:GetStepHeight() and self:GetRangeSquaredTo(segment.pos) < path:GetGoalTolerance() ^ 2 then dojump = false end
				if dojump then
					local result = self:CalcJumpHeightOverObstacles(segment.pos)
					if isnumber(result) then
						self:JumpToPos(segment.pos, result)
						local ang = self:GetAngles()
						path:Update(self)
						self:SetAngles(ang)
					elseif result == true then
						local dir = pos - segment.pos
						dir.z = 0
						dir:Normalize()
						self:Approach(pos + dir * 100)
					elseif istable(result) then
						self:JumpToPos(result.pos, result.height)
					else
						self:JumpToPos(segment.pos, self.MaxJumpToPosHeight)
					end
					dontupdate = true
				end
			end
		end
	end
	if not dontupdate then
		if self.loco:IsOnGround() or self.m_Ladder then
			local ang = self:GetAngles()
			path:Update(self)
			self:SetAngles(ang)
			local phys = self:GetPhysicsObject()
			if IsValid(phys) then phys:SetAngles(angle_zero) end
		else
			self:Approach(segment.pos)
		end
	end
	if self.DrawPath:GetBool() then path:Draw() end
	local range = self:GetRangeSquaredTo(self:GetPathPos())
	if not path:IsValid() and range <= self.m_PathOptions.tolerance ^ 2 or range < self.PathGoalToleranceFinal ^ 2 then
		path:Invalidate()
		return true
	end
	return false
end

function ENT:Jump()
	if self.m_Ladder then self:DetachFromLadder() end
	if not self.loco:IsOnGround() then return end
	local vel = self.loco:GetVelocity()
	vel.z = math.sqrt(2 * self.loco:GetGravity() * self.JumpHeight)
	self.loco:Jump()
	self.loco:SetVelocity(vel)
	self:SetupActivity()
	self:SetupCollisionBounds()
	self:MakeFootstepSound(1)
	self.m_Jumping = true
	self:RunTask("OnJump")
end

function ENT:IsJumping()
	return self.m_Jumping or false
end

function ENT:OnLandOnGround(ent)
	if self.m_Jumping then
		self.m_Jumping = false
		self.m_JumpingToPos = false
		self.loco:SetStepHeight(self.StepHeight)
		if not self:IsPostureActive() then self:SetupActivity() end
		self:SetupCollisionBounds()
	end
	local fallspeed = self.m_FallSpeed
	if fallspeed >= 300 then
		local layer = self:AddGesture(self:TranslateActivity(ACT_LAND))
		self:SetLayerPlaybackRate(layer, 1)
		if fallspeed >= 530 then
			self:MakeFootstepSound(1)
			self:EmitSound("Player.FallDamage", 75, math.random(90, 110), 0.75)
			local dmg = DamageInfo()
			dmg:SetAttacker(game.GetWorld())
			dmg:SetInflictor(game.GetWorld())
			dmg:SetDamageType(DMG_FALL)
			dmg:SetDamage(self:GetFallDamage(fallspeed))
			dmg:SetDamagePosition(self:GetPos())
			self:TakeDamageInfo(dmg)
		else
			self:MakeFootstepSound(0.85)
		end
	end
	self:RunTask("OnLandOnGround", ent)
end

function ENT:GetFootstepSoundTime()
	local time = 350
	local speed = self:GetDesiredSpeed()
	if speed <= 100 then time = 400
	elseif speed <= 300 then time = 350
	else time = 250 end
	if self:IsCrouching() then time = time + 50 end
	return time
end

function ENT:MakeFootstepSound(volume, surface)
	local foot = self.m_FootstepFoot
	self.m_FootstepFoot = not foot
	self.m_FootstepTime = CurTime()
	if not surface then
		local tr = util.TraceEntity({start = self:GetPos(), endpos = self:GetPos() - Vector(0, 0, 5), filter = self, mask = self:GetSolidMask(), collisiongroup = self:GetCollisionGroup()}, self)
		surface = tr.SurfaceProps
	end
	if not surface then return end
	local surface = util.GetSurfaceData(surface)
	if not surface then return end
	local sound = foot and surface.stepRightSound or surface.stepLeftSound
	if sound then
		local pos = self:GetPos()
		local filter = RecipientFilter()
		filter:AddPAS(pos)
		if not self:OnFootstep(pos, foot, sound, volume, filter) then
			self:EmitSound(sound, 75, 100, volume, CHAN_BODY, 0, 0, filter)
		end
	end
end

function TraceHit(tr)
	return tr.Hit
end

function TryStuck(self, pos, t, tr)
	t.start = pos
	t.endpos = pos
	util.TraceHull(t)
	if not TraceHit(tr) then
		self:SetPos(pos)
		self.loco:SetVelocity(vector_origin)
		self.loco:ClearStuck()
		self:OnUnStuck()
		return true
	end
	return false
end

function ENT:OnStuck()
	self.m_Stuck = true
	if self.m_Ladder then
		self:DetachFromLadder(nil, "stuck")
	end
	self:GetPath():Invalidate()
	self:RunTask("OnStuck")
	local pos = self:GetPos()
	local b1, b2 = self:GetCollisionBounds()
	if not self.loco:IsOnGround() then
		b1.x = b1.x - 1
		b1.y = b1.y - 1
		b2.x = b2.x + 1
		b2.y = b2.y + 1
	end
	local tr = {}
	local t = {
		mask = self:GetSolidMask(),
		collisiongroup = self:GetCollisionGroup(),
		output = tr,
		filter = function(ent) return ent != self and not self:StuckCheckShouldIgnoreEntity(ent) end,
		mins = b1,
		maxs = b2,
	}
	local w = b2.x - b1.x
	for z = 0, w * 1.2, w * 0.2 do
		for x = 0, w * 1.2, w * 0.2 do
			for y = 0, w * 1.2, w * 0.2 do
				if TryStuck(self, pos + Vector(x, y, z), t, tr) then return end
				if TryStuck(self, pos + Vector(-x, y, z), t, tr) then return end
				if TryStuck(self, pos + Vector(x, -y, z), t, tr) then return end
				if TryStuck(self, pos + Vector(-x, -y, z), t, tr) then return end
				if TryStuck(self, pos + Vector(x, y, -z), t, tr) then return end
				if TryStuck(self, pos + Vector(-x, y, -z), t, tr) then return end
				if TryStuck(self, pos + Vector(x, -y, -z), t, tr) then return end
				if TryStuck(self, pos + Vector(-x, -y, -z), t, tr) then return end
			end
		end
	end
end

function ENT:OnUnStuck()
	self.m_Stuck = false
	self.m_StuckTime = CurTime() + 1
	self.m_StuckTime2 = 0
	self:RunTask("OnUnStuck")
end

function ENT:StuckCheckShouldIgnoreEntity(ent)
	return self:RunTask("StuckCheckShouldIgnoreEntity", ent)
end

function ENT:StuckCheck()
	if CurTime() >= self.m_StuckTime then
		self.m_StuckTime = CurTime() + math.Rand(0.75, 1.25)
		local pos = self:GetPos()
		if self.m_StuckPos != pos then
			self.m_StuckPos = pos
			self.m_StuckTime2 = 0
			if self.m_Stuck then self:OnUnStuck() end
		else
			local b1, b2 = self:GetCollisionBounds()
			if not self.loco:IsOnGround() then
				b1.x = b1.x - 1
				b1.y = b1.y - 1
				b2.x = b2.x + 1
				b2.y = b2.y + 1
			end
			local tr = util.TraceHull({
				start = pos, endpos = pos,
				filter = function(ent) return ent != self and not self:StuckCheckShouldIgnoreEntity(ent) end,
				mask = self:GetSolidMask(),
				collisiongroup = self:GetCollisionGroup(),
				mins = b1, maxs = b2,
			})
			if not self.m_Stuck then
				if TraceHit(tr) then
					self.m_StuckTime2 = self.m_StuckTime2 + math.Rand(0.75, 1.25)
					if self.m_StuckTime2 >= 1.25 then self:OnStuck() end
				else
					self.m_StuckTime2 = 0
				end
			else
				if not TraceHit(tr) then self:OnUnStuck() end
			end
		end
	end
end

function ENT:SetHullType(type) self.m_HullType = type end
function ENT:GetHullType() return self.m_HullType end
function ENT:SetDuckHullType(type) self.m_DuckHullType = type end
function ENT:GetDuckHullType() return self.m_DuckHullType end

function ENT:CalcJumpHeightOverObstacles(goal, maxheight, start)
	maxheight = maxheight or self.MaxJumpToPosHeight
	start = start or self:GetPos()
	if goal.z - start.z > maxheight then return end
	local bounds = self.CanCrouch and self.CrouchCollisionBounds or self.CollisionBounds
	local mins, maxs = Vector(bounds[1]), bounds[2]
	local step = self.StepHeight
	local tolerance = math.max(maxs.x - mins.x, maxs.y - mins.y, maxs.z - mins.z, self:PathIsValid() and self:GetPath():GetGoalTolerance() or self.PathGoalTolerance)
	local width = maxs.x - mins.x
	local MIN_JUMP_DIST = 10
	mins.z = mins.z + step
	local dir2 = goal - start
	dir2.z = 0
	dir2:Normalize()
	local apexs, jumpapex = {}, Vector(goal)
	while true do
		local cstart = start
		if #apexs > 0 then
			local apex = apexs[#apexs]
			local from = #apexs > 1 and apexs[#apexs - 1].endpos or start
			while true do
				tr.start = from
				tr.endpos = apex.endpos
				util.TraceHull(tr)
				if not result.Hit then
					apex.start = apex.endpos
					break
				end
				tr.start = apex.start
				tr.endpos = apex.endpos
				util.TraceHull(tr)
				if not result.Hit then
					tr.start = from
					tr.endpos = apex.start
					util.TraceHull(tr)
					if not result.Hit then break end
				end
				if apex.start.z - start.z >= maxheight then return nil
				else
					apex.start.z = math.min(apex.start.z + (step < 5 and 5 or step), start.z + maxheight + 0.1)
					apex.endpos.z = apex.start.z
				end
			end
			if math.DistanceSqr(start.x, start.y, apex.start.x, apex.start.y) < math.DistanceSqr(start.x, start.y, jumpapex.x, jumpapex.y) then
				jumpapex.x = apex.start.x
				jumpapex.y = apex.start.y
			end
			if apex.start.z > jumpapex.z then jumpapex.z = apex.start.z end
			cstart = apex.endpos
		end
		local dir = goal - cstart
		local len = math.max(MIN_JUMP_DIST, dir:Length() - tolerance)
		dir:Normalize()
		tr.start = cstart
		tr.endpos = cstart + dir * len
		util.TraceHull(tr)
		if result.Hit then
			if result.Fraction == 0 then return #apexs == 0 end
			if #apexs == 0 and result.HitPos:DistToSqr(start) < MIN_JUMP_DIST * MIN_JUMP_DIST then return true end
			local endpos = result.HitPos + dir2 * width * 2
			local dir = goal - endpos
			dir.z = 0
			dir:Normalize()
			if dir2:Dot(dir) < 0.8 then return nil end
			apexs[#apexs + 1] = {start = result.HitPos, endpos = endpos}
		else
			local fr = math.Clamp(math.Distance(jumpapex.x, jumpapex.y, start.x, start.y) / math.Distance(goal.x, goal.y, start.x, start.y), 0, 1)
			local height = (jumpapex.z - start.z) / fr
			if height > maxheight then
				local firstapex = apexs[1]
				if not firstapex then return end
				local pos = (firstapex.start + firstapex.endpos) / 2
				return {pos = pos, height = pos.z - start.z}
			end
			return height
		end
	end
end

function ENT:JumpToPos(pos, height)
	if not height then
		local result = self:CalcJumpHeightOverObstacles(pos)
		height = isnumber(result) and result or 0
	end
	if height < self.loco:GetJumpHeight() then height = self.loco:GetJumpHeight() end
	local curpos = self:GetPos()
	if pos.z - curpos.z > self.MaxJumpToPosHeight then
		pos = Vector(pos.x, pos.y, curpos.z + self.MaxJumpToPosHeight)
	end
	local dir = pos - curpos
	local dist = dir:Length()
	dir:Normalize()
	local g = self.loco:GetGravity()
	local maxh = math.max(pos.z, curpos.z) + height
	local h1 = maxh - curpos.z
	local h2 = maxh - pos.z
	local t1 = math.sqrt(2 / g * h1)
	local t2 = math.sqrt(2 / g * h2)
	local t = t1 + t2
	self:Jump()
	self.loco:SetVelocity(Vector(dir.x * dist / t, dir.y * dist / t, math.sqrt(2 * g * h1)))
	self.m_JumpingToPos = true
end

hook.Add("OnPhysgunPickup", "AaronBot", function(ply, ent)
	if ent.AaronBot then
		ent.m_Physguned = true
		ent:UpdateGravity()
	end
end)

hook.Add("PhysgunDrop", "AaronBot", function(ply, ent)
	if ent.AaronBot then
		ent.m_Physguned = false
		ent:UpdateGravity()
	end
end)