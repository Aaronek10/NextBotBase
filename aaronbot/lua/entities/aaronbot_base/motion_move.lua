-- motion part: move
AaronBotMotion = AaronBotMotion or {}
local M = AaronBotMotion
local function IsAngleEqual(ang1, ang2)
	return math.abs(math.AngleDifference(ang1.p, ang2.p)) < 0.01
		and math.abs(math.AngleDifference(ang1.y, ang2.y)) < 0.01
		and math.abs(math.AngleDifference(ang1.r, ang2.r)) < 0.01
end
local function UpdateLadders()
	if M.UpdateLadders then M.UpdateLadders() end
end
local function TraceHit(tr) return tr.Hit end
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
			for l = 1, #M.Ladders do
				local ladder = M.Ladders[l]
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
