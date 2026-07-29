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

local GO_NORTH = 0
local GO_EAST = 1
local GO_SOUTH = 2
local GO_WEST = 3
local GO_LADDER_UP = 4
local GO_LADDER_DOWN = 5
local GO_JUMP = 6
local GO_ELEVATOR_UP = 7
local GO_ELEVATOR_DOWN = 8

local ON_GROUND = 0
local DROP_DOWN = 1
local CLIMB_UP = 2
local JUMP_OVER_GAP = 3
local LADDER_UP = 4
local LADDER_DOWN = 5

local Ladders, LaddersUpdate = {}, nil
local function UpdateLadders()
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

local function IsAngleEqual(ang1, ang2)
	return math.abs(math.AngleDifference(ang1.p, ang2.p)) < 0.01
		and math.abs(math.AngleDifference(ang1.y, ang2.y)) < 0.01
		and math.abs(math.AngleDifference(ang1.r, ang2.r)) < 0.01
end

function ENT:SetupEyeAngles()
	local angp = self.m_PitchAim
	local angy = self:GetAngles().y
	local desired = self:GetDesiredEyeAngles()
	local punch = self:GetViewPunchAngles()
	if self:IsControlledByPlayer() then
		desired = self:GetControlPlayer():EyeAngles()
	end
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

local IdleActivity = ACT_HL2MP_IDLE
local IdleActivityTranslate = {
	[ACT_MP_STAND_IDLE] = IdleActivity,
	[ACT_MP_WALK] = IdleActivity + 1,
	[ACT_MP_RUN] = IdleActivity + 2,
	[ACT_MP_CROUCH_IDLE] = IdleActivity + 3,
	[ACT_MP_CROUCHWALK] = IdleActivity + 4,
	[ACT_MP_ATTACK_STAND_PRIMARYFIRE] = IdleActivity + 5,
	[ACT_MP_ATTACK_CROUCH_PRIMARYFIRE] = IdleActivity + 5,
	[ACT_MP_RELOAD_STAND] = IdleActivity + 6,
	[ACT_MP_RELOAD_CROUCH] = IdleActivity + 7,
	[ACT_MP_JUMP] = ACT_HL2MP_JUMP_SLAM,
	[ACT_MP_SWIM] = IdleActivity + 9,
	[ACT_LAND] = ACT_LAND,
}

function ENT:TranslateActivity(act)
	local task = self:RunTask("TranslateActivity", act)
	if task then return task end
	if self:HasWeapon() then
		self.m_PassIsNPCCheck = false
		local newact
		ProtectedCall(function() newact = self:GetActiveLuaWeapon():TranslateActivity(act) end)
		self.m_PassIsNPCCheck = true
		return newact
	end
	return IdleActivityTranslate[act] or IdleActivity
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
						local ladder = Ladders[l]
						local dot = dir:Dot(ladder:GetNormal())
						if dot < -0.5 and curpos.z > ladder:GetBottom().z - step and curpos.z < ladder:GetTop().z - step and util.DistanceToLine(ladder:GetBottom(), ladder:GetTop(), curpos) < ladder:GetWidth() + width then
							self:AttachToLadder(ladder)
							break
						end
					end
				end
			end
		end
	else
		local pos = self:GetPos()
		if not self.m_LadderJustAttached then
			if pos.z < ladder.Bottom.z or pos.z > ladder.Top.z or util.DistanceToLine(ladder.Bottom, ladder.Top, pos) > self:GetHullWidth() / 2 then
				self:DetachFromLadder()
			else
				local goal = self.m_LadderApproach
				self.loco:SetVelocity(goal and (goal - pos) / interval or vector_origin)
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

function ENT:ShouldRun()
	if self:IsControlledByPlayer() then
		return self:ControlPlayerKeyDown(IN_SPEED)
	end
	return self:RunTask("ShouldRun") or false
end

function ENT:ShouldWalk()
	if self:IsControlledByPlayer() then
		return self:ControlPlayerKeyDown(IN_WALK)
	end
	return self:RunTask("ShouldWalk") or false
end

function ENT:ShouldCrouch()
	if not self.CanCrouch then return false end
	if self:IsControlledByPlayer() then
		return self:ControlPlayerKeyDown(IN_DUCK)
	end
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
	local options = self.m_PathOptions
	if not self.m_Ladder then
		local range = self:GetRangeSquaredTo(pos)
		if range < options.tolerance ^ 2 or range < self.PathGoalToleranceFinal ^ 2 then
			path:Invalidate()
			return true
		end
		if path:GetAge() > options.recompute and self.loco:IsOnGround() then
			path:ResetAge()
			if not self:ComputePath(pos, options.generator) then return false end
		end
	end
	if self:MoveAlongPath(lookatgoal) then return true end
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
		local dir = pos - curpos
		dir:Normalize()
		local up = dir.z * self.LadderClimbSpeed * self.BehaveInterval
		local ladderdir = self.m_Ladder.Top - self.m_Ladder.Bottom
		local length = ladderdir:Length()
		ladderdir:Normalize()
		local fr = (curpos.z - self.m_Ladder.Bottom.z) / (self.m_Ladder.Top.z - self.m_Ladder.Bottom.z)
		local newfr = (fr * length + up) / length
		pos = self.m_Ladder.Bottom + (self.m_Ladder.Top - self.m_Ladder.Bottom) * newfr
		local filter = self:GetChildren()
		filter[#filter + 1] = self
		local mins, maxs = self:GetCollisionBounds()
		local tr = util.TraceHull({start = curpos, endpos = pos, mins = mins, maxs = maxs, mask = self:GetSolidMask(), filter = filter})
		self.m_LadderApproach = pos
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
	self.m_Ladder = {Bottom = bottom + normal * width * 0.5, Top = top + normal * width * 0.5, Normal = normal}
	self.m_LadderApproach = nil
	self.m_LadderJustAttached = true
	self.m_Jumping = false
	self.m_JumpingToPos = false
	local len = self.m_Ladder.Top.z - self.m_Ladder.Bottom.z
	local fr = math.Clamp(math.Clamp(self:GetPos().z - self.m_Ladder.Bottom.z, self.StepHeight, len - self.StepHeight) / len, 0, 1)
	local mount = self.m_Ladder.Bottom + (self.m_Ladder.Top - self.m_Ladder.Bottom) * fr
	self.loco:SetStepHeight(1)
	self:UpdateGravity()
	if self.loco:IsOnGround() then self.loco:Jump() end
	self.loco:SetVelocity((mount - self:GetPos()) / self.BehaveInterval)
end

function ENT:DetachFromLadder()
	self.m_Ladder = nil
	self.m_LadderApproach = nil
	self.m_LadderJustAttached = nil
	self.loco:SetStepHeight(self.StepHeight)
	self:UpdateGravity()
	if self:PathIsValid() and not self:UsingNodeGraph() and self:GetPath():GetCurrentGoal() and self:GetPath():GetCurrentGoal().ladder then
		self:GetPath():Update(self)
	end
end

function ENT:IsUsingLadder()
	return self.m_Ladder and true or false
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
			local ladder = self.m_Ladder
			if ladder then
				dontupdate = true
				self:Approach(pos + Vector(0, 0, segment.how == GO_LADDER_UP and 1 or -1))
				self:SetDesiredEyeAngles((segment.how == GO_LADDER_UP and ladder.Top - ladder.Bottom or ladder.Bottom - ladder.Top):Angle())
			else
				local ladderstart = segment.how == GO_LADDER_UP and segment.ladder:GetBottom() or segment.ladder:GetTop()
				local ladderend = segment.how == GO_LADDER_UP and segment.ladder:GetTop() or segment.ladder:GetBottom()
				local nearend = math.abs(pos.z - ladderend.z) < math.abs(pos.z - ladderstart.z)
				local dest = nearend and path:NextSegment().pos or ladderstart + segment.ladder:GetNormal() * self:GetHullWidth(true) / 2
				if not nearend then
					local range = (dest - pos):Length2D()
					if range < 50 + self.loco:GetDesiredSpeed() then
						dontupdate = true
						if range < 5 then
							self:AttachToLadder(segment.ladder)
							self:SetPos(dest)
							self:Approach(ladderend)
						else
							self:Approach(dest)
						end
					end
				else
					self:Approach(dest)
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

function ENT:OnFootstep(pos, foot, sound, volume, filter)
	return self:RunTask("OnFootstep", pos, foot, sound, volume, filter)
end

function ENT:ProcessFootsteps()
	if not self.loco:IsOnGround() then return end
	local foot = self.m_FootstepFoot
	local time = self.m_FootstepTime
	local curspeed = self:GetCurrentSpeed()
	if curspeed > self.WalkSpeed and CurTime() - time >= self:GetFootstepSoundTime() / 1000 then
		local walk = curspeed < self.RunSpeed
		local tr = util.TraceEntity({start = self:GetPos(), endpos = self:GetPos() - Vector(0, 0, 5), filter = self, mask = self:GetSolidMask(), collisiongroup = self:GetCollisionGroup()}, self)
		local surface = util.GetSurfaceData(tr.SurfaceProps)
		if not surface then return end
		local m = surface.material
		local vol = 0
		if m == MAT_CONCRETE then vol = walk and 0.2 or 0.5
		elseif m == MAT_METAL then vol = walk and 0.2 or 0.5
		elseif m == MAT_DIRT then vol = walk and 0.25 or 0.55
		elseif m == MAT_VENT then vol = walk and 0.4 or 0.7
		elseif m == MAT_GRATE then vol = walk and 0.2 or 0.5
		elseif m == MAT_TILE then vol = walk and 0.2 or 0.5
		elseif m == MAT_SLOSH then vol = walk and 0.2 or 0.5 end
		self:MakeFootstepSound(vol, tr.SurfaceProps)
	end
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

local function TraceHit(tr)
	return tr.Hit
end

local function TryStuck(self, pos, t, tr)
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
					if self.m_StuckTime2 >= 5 then self:OnStuck() end
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
	local filter = self:GetChildren()
	filter[#filter + 1] = self
	local result = {}
	local tr = {mins = mins, maxs = maxs, filter = filter, mask = self:GetSolidMask(), collisiongroup = self:GetCollisionGroup(), output = result}
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
