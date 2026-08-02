-- Ladder fixes (no MoveAlongPath wrapper — previous wrapper broke path following)
--
-- Changes vs motion.lua:
-- 1) Attach respects exit cooldown
-- 2) Detach pushes onto landing + sets cooldown (prevents re-grab at the lip)
-- 3) LocomotionUpdate: SB-style end detect (z past Top/Bottom), velocity = (goal-pos)/dt
-- 4) MoveAlongPath: full clean copy with ladder climb like SB (Approach ±Z)
--    and exit only near the end (Top-4 / Bottom+4), not Top-20

local LADDER_EXIT_COOLDOWN = 0.75

function ENT:AttachToLadder(ladder)
	if not ladder then return self:DetachFromLadder() end
	if self.m_LadderCooldown and CurTime() < self.m_LadderCooldown then return end

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
	self.m_LadderCooldown = CurTime() + LADDER_EXIT_COOLDOWN

	self.loco:SetStepHeight(self.StepHeight)
	self:UpdateGravity()

	local pos = self:GetPos()
	local dest = exitPos
	if not isvector(dest) then
		if math.abs(pos.z - ladder.Top.z) <= math.abs(pos.z - ladder.Bottom.z) then
			dest = ladder.Top + ladder.Normal * 36
			dest.z = ladder.Top.z + 12
		else
			dest = ladder.Bottom + ladder.Normal * 36
			dest.z = ladder.Bottom.z + 4
		end
	end

	if self:PathIsValid() and not self:UsingNodeGraph() then
		local goal = self:GetPath():GetCurrentGoal()
		if goal and goal.ladder then
			local ang = self:GetAngles()
			self:GetPath():Update(self)
			self:SetAngles(ang)
		end
	end

	local away = dest - pos
	if away:LengthSqr() < 1 then
		away = ladder.Normal
	else
		away:Normalize()
	end

	local land = pos + away * 28
	if pos.z >= ladder.Top.z - 4 then
		land.z = math.max(ladder.Top.z + 4, dest.z)
	else
		land.z = pos.z
	end
	self:SetPos(land)
	self.loco:SetVelocity(away * 180 + Vector(0, 0, 60))
	self:RunTask("OnLadderExit", reason)
end

function ENT:LocomotionUpdate(interval)
	self:UpdatePhysicsObject()
	if self.m_Physguned then
		self.loco:SetVelocity(vector_origin)
	end

	local ladder = self.m_Ladder
	if not ladder then
		if self.CanUseLadder and not (self.m_LadderCooldown and CurTime() < self.m_LadderCooldown) then
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
						if dot < -0.5
							and curpos.z > lad:GetBottom().z - step
							and curpos.z < lad:GetTop().z - step * 2
							and util.DistanceToLine(lad:GetBottom(), lad:GetTop(), curpos) < lad:GetWidth() + width then
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
			local below = pos.z < ladder.Bottom.z
			local above = pos.z > ladder.Top.z

			if offAxis or below or above then
				local reason = above and "past_top" or (below and "past_bottom" or "off_axis")
				local exitPos
				if above then
					exitPos = ladder.Top + ladder.Normal * 36
					exitPos.z = ladder.Top.z + 12
				elseif below then
					exitPos = ladder.Bottom + ladder.Normal * 36
					exitPos.z = ladder.Bottom.z + 4
				end
				self:DetachFromLadder(exitPos, reason)
			else
				if dist2d > 4 then
					local snap = axisPos
					snap.z = pos.z
					self:SetPos(snap)
				end
				local goal = self.m_LadderApproach
				if goal then
					local dt = interval
					if not dt or dt <= 0 then dt = self.BehaveInterval or 0.1 end
					if dt < 0.01 then dt = 0.01 end
					self.loco:SetVelocity((goal - pos) / dt)
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
				-- On ladder: climb like SB (Approach ±Z). LocomotionUpdate applies velocity
				-- and detaches when past Top/Bottom. Only force-exit near the lip.
				dontupdate = true
				self:Approach(pos + Vector(0, 0, goingUp and 1 or -1))
				self:SetDesiredEyeAngles((goingUp and (ladderData.Top - ladderData.Bottom) or (ladderData.Bottom - ladderData.Top)):Angle())

				if goingUp and pos.z >= ladderData.Top.z - 4 then
					local nextSeg = path:NextSegment()
					local exitPos = nextSeg and nextSeg.pos or nil
					if not exitPos then
						exitPos = ladderData.Top + ladderData.Normal * 36
						exitPos.z = ladderData.Top.z + 12
					end
					self:DetachFromLadder(exitPos, "reached_top")
					dontupdate = false
				elseif not goingUp and pos.z <= ladderData.Bottom.z + 4 then
					local nextSeg = path:NextSegment()
					local exitPos = nextSeg and nextSeg.pos or nil
					if not exitPos then
						exitPos = ladderData.Bottom + ladderData.Normal * 36
						exitPos.z = ladderData.Bottom.z + 4
					end
					self:DetachFromLadder(exitPos, "reached_bottom")
					dontupdate = false
				end
			else
				-- Not yet on ladder: approach mount point / attach
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
			if (segment.how == GO_JUMP or segment.how <= GO_WEST and prev and prev.area:HasAttributes(NAV_MESH_JUMP))
				and self.loco:IsOnGround() and self.loco:GetJumpHeight() > 0 then
				local dojump = true
				local deltaz = segment.pos.z - pos.z
				if deltaz <= 0 and (segment.pos - pos):Length2DSqr() < path:GetGoalTolerance() ^ 2 then
					dojump = false
				elseif deltaz < self.loco:GetStepHeight() and self:GetRangeSquaredTo(segment.pos) < path:GetGoalTolerance() ^ 2 then
					dojump = false
				end

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
	local tol = (self.m_PathOptions and self.m_PathOptions.tolerance) or self.PathGoalTolerance or 25
	if (not path:IsValid() and range <= tol * tol) or range < (self.PathGoalToleranceFinal or 25) ^ 2 then
		path:Invalidate()
		return true
	end
	return false
end
