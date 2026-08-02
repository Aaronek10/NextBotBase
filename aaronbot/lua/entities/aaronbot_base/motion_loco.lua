-- motion part: loco
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
				if #M.Ladders > 0 then
					local curpos = self:GetPos()
					local step = self.StepHeight
					local width = self:GetHullWidth() / 2
					dir:Normalize()
					for l = 1, #M.Ladders do
						local ladder = M.Ladders[l]
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
