-- AaronBot motion fixes (post-merge)
-- Loaded after motion.lua from init.lua

function ENT:IsPostureActive()
	return self.m_CurPosture and (not self.m_CurPosture[2] or CurTime() < self.m_CurPosture[1]) or false
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
			end
		end
		self.m_LadderApproach = nil
		self.m_LadderJustAttached = nil
	end
	self:SetupSpeed()
	self:SetupMotionType()
	self:ProcessFootsteps()
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
				self.m_LadderApproach = climbTarget
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

function ENT:OnFootstep(pos, foot, sound, volume, filter)
	return self:RunTask("OnFootstep", pos, foot, sound, volume, filter)
end

function ENT:ProcessFootsteps()
	if not self.loco:IsOnGround() then return end
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
