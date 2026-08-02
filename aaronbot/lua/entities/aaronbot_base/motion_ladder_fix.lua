-- Ladder top-exit fix
-- Problem: we detached at Top-20 while still inside the attach z-range,
-- so the bot re-grabbed the ladder every tick and never stepped onto the landing.
--
-- Approach (aligned with SB ANB):
-- 1) Climb with Approach(pos +/- up) so velocity overshoots past Top.z
-- 2) Detach when z is past the end (not 20 units early)
-- 3) Brief cooldown after detach so Approach/path cannot re-attach immediately
-- 4) Stronger push onto the landing (next segment or Top + Normal)

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
		-- Prefer the nearer end; push along ladder normal onto the landing side
		if math.abs(pos.z - ladder.Top.z) <= math.abs(pos.z - ladder.Bottom.z) then
			dest = ladder.Top + ladder.Normal * 36
			dest.z = ladder.Top.z + 12
		else
			dest = ladder.Bottom + ladder.Normal * 36
			dest.z = ladder.Bottom.z + 4
		end
	end

	-- Advance path past the ladder segment if we are still on it
	if self:PathIsValid() and not self:UsingNodeGraph() then
		local goal = self:GetPath():GetCurrentGoal()
		if goal and goal.ladder then
			local ang = self:GetAngles()
			self:GetPath():Update(self)
			self:SetAngles(ang)
		end
	end

	-- Nudge onto landing so we are outside attach range next tick
	local away = dest - pos
	if away:LengthSqr() < 1 then
		away = ladder.Normal
	else
		away:Normalize()
	end

	local land = Vector(pos.x, pos.y, pos.z) + away * 28
	land.z = math.max(pos.z, dest.z)
	-- Only soft-set XY; keep current Z if already above top so we do not slam into floor
	if pos.z >= ladder.Top.z - 4 then
		land.z = math.max(ladder.Top.z + 4, dest.z)
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
						-- Require being clearly below top so post-exit re-grab cannot happen at the lip
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
			-- SB-style end detection: past top/bottom or too far off axis → detach
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
				-- Keep snapped to axis while climbing
				if dist2d > 4 then
					local snap = axisPos
					snap.z = pos.z
					self:SetPos(snap)
				end
				-- SB-style velocity: (goal - pos) / interval so we overshoot the end naturally
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

-- Override only the on-ladder climb + top/bottom exit thresholds inside MoveAlongPath
-- by redefining the whole function would be large; instead patch via a thin wrapper
-- that adjusts climb target and exit. Full MoveAlongPath is still in motion.lua;
-- we replace the on-ladder Approach behaviour by setting climb via Approach each tick
-- the same way SB does when our MoveAlongPath is mid-ladder.

local PATH_MOVE = ENT.MoveAlongPath
function ENT:MoveAlongPath(lookatgoal)
	local path = self:GetPath()
	local segment = path:GetCurrentGoal()
	if not segment then return false end

	-- When already on a ladder segment, drive climb like SB (Approach ±Z)
	-- and only detach once we are essentially at the end — not 20u early.
	if not self:UsingNodeGraph()
		and segment.ladder
		and (segment.how == GO_LADDER_UP or segment.how == GO_LADDER_DOWN)
		and self.m_Ladder then

		local goingUp = segment.how == GO_LADDER_UP
		local ladderData = self.m_Ladder
		local pos = self:GetPos()

		if lookatgoal then
			local ang = (segment.pos - self:GetShootPos()):Angle()
			ang.p = 0
			self:SetDesiredEyeAngles(ang)
		end

		self:SetDesiredEyeAngles((goingUp and (ladderData.Top - ladderData.Bottom) or (ladderData.Bottom - ladderData.Top)):Angle())

		-- Climb continuously; LocomotionUpdate will detach when past Top/Bottom
		self:Approach(pos + Vector(0, 0, goingUp and 1 or -1))

		-- Explicit exit once we reach the lip (small margin only)
		if goingUp and pos.z >= ladderData.Top.z - 4 then
			local nextSeg = path:NextSegment()
			local exitPos = nextSeg and nextSeg.pos or nil
			if not exitPos then
				exitPos = ladderData.Top + ladderData.Normal * 36
				exitPos.z = ladderData.Top.z + 12
			end
			self:DetachFromLadder(exitPos, "reached_top")
			-- Fall through to normal path update after detach
		elseif not goingUp and pos.z <= ladderData.Bottom.z + 4 then
			local nextSeg = path:NextSegment()
			local exitPos = nextSeg and nextSeg.pos or nil
			if not exitPos then
				exitPos = ladderData.Bottom + ladderData.Normal * 36
				exitPos.z = ladderData.Bottom.z + 4
			end
			self:DetachFromLadder(exitPos, "reached_bottom")
		else
			if self.DrawPath:GetBool() then path:Draw() end
			return false
		end
	end

	return PATH_MOVE(self, lookatgoal)
end
