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
