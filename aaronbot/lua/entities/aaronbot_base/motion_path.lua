-- motion part: path
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
