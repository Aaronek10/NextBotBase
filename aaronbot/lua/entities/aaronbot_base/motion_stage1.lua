--[[
	AaronBot Stage 1 motion improvements
	Included after motion.lua — overrides ladder, stuck, and path soft-commit.
]]

local function SnapToLadderAxis(ladderBottom, ladderTop, point)
	local ladderDirection = (ladderTop - ladderBottom):GetNormalized()
	local bottomToPoint = point - ladderBottom
	local projected = ladderDirection * bottomToPoint:Dot(ladderDirection)
	return ladderBottom + projected
end

local function Dist2D(pos1, pos2)
	local d = pos1 - pos2
	return d:Length2D()
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

	local away = dest - pos
	if away:LengthSqr() < 1 then
		away = ladder.Normal
	else
		away:Normalize()
	end
	self.loco:SetVelocity(away * 120 + Vector(0, 0, 40))
	self:RunTask("OnLadderExit", reason)
end

function ENT:HandlePathRemovedWhileOnLadder()
	if not self.m_Ladder then return end
	if self:PathIsValid() then return end
	self:DetachFromLadder(self:GetPos(), "path_removed")
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
	local function TryStuckLocal(self, p, t, tr)
		t.start = p
		t.endpos = p
		util.TraceHull(t)
		if not tr.Hit then
			self:SetPos(p)
			self.loco:SetVelocity(vector_origin)
			self.loco:ClearStuck()
			self:OnUnStuck()
			return true
		end
		return false
	end
	for z = 0, w * 1.2, w * 0.2 do
		for x = 0, w * 1.2, w * 0.2 do
			for y = 0, w * 1.2, w * 0.2 do
				if TryStuckLocal(self, pos + Vector(x, y, z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(-x, y, z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(x, -y, z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(-x, -y, z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(x, y, -z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(-x, y, -z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(x, -y, -z), t, tr) then return end
				if TryStuckLocal(self, pos + Vector(-x, -y, -z), t, tr) then return end
			end
		end
	end
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
				if tr.Hit then
					self.m_StuckTime2 = self.m_StuckTime2 + math.Rand(0.75, 1.25)
					if self.m_StuckTime2 >= 1.25 then self:OnStuck() end
				else
					self.m_StuckTime2 = 0
				end
			else
				if not tr.Hit then self:OnUnStuck() end
			end
		end
	end
end

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
					local snap = Vector(axisPos.x, axisPos.y, pos.z)
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
