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
		if Dist2D(curpos, axisPos) > 2 then
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
