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
