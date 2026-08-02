-- Motion Type Enums
AARONBOT_MOTIONTYPE_IDLE = 0
AARONBOT_MOTIONTYPE_MOVE = 1
AARONBOT_MOTIONTYPE_RUN = 2
AARONBOT_MOTIONTYPE_WALK = 3
AARONBOT_MOTIONTYPE_CROUCH = 4
AARONBOT_MOTIONTYPE_CROUCHWALK = 5
AARONBOT_MOTIONTYPE_JUMPING = 6
AARONBOT_MOTIONTYPE_LADDER = 7

ENT.MotionTypeActivities = {
	[AARONBOT_MOTIONTYPE_IDLE] = ACT_MP_STAND_IDLE,
	[AARONBOT_MOTIONTYPE_MOVE] = ACT_MP_RUN,
	[AARONBOT_MOTIONTYPE_RUN] = ACT_MP_RUN,
	[AARONBOT_MOTIONTYPE_WALK] = ACT_MP_WALK,
	[AARONBOT_MOTIONTYPE_CROUCH] = ACT_MP_CROUCH_IDLE,
	[AARONBOT_MOTIONTYPE_CROUCHWALK] = ACT_MP_CROUCHWALK,
	[AARONBOT_MOTIONTYPE_JUMPING] = ACT_MP_JUMP,
	[AARONBOT_MOTIONTYPE_LADDER] = ACT_MP_JUMP,
}

local GO_NORTH = 0
local GO_EAST = 1
local GO_SOUTH = 2
local GO_WEST = 3
local GO_LADDER_UP = 4
local GO_LADDER_DOWN = 5
local GO_JUMP = 6
local GO_ELEVATOR_UP = 7
local GO_ELEVATOR_DOWN = 8

local ON_GROUND = 0
local DROP_DOWN = 1
local CLIMB_UP = 2
local JUMP_OVER_GAP = 3
local LADDER_UP = 4
local LADDER_DOWN = 5

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

-- NOTE: Full motion body continues in motion_core via runtime load below if present.
-- Stage 1 improvements: motion_stage1.lua (included from init.lua after this file).

function ENT:SetMotionType(type)
	self.m_MotionType = type
end

function ENT:GetMotionType()
	return self.m_MotionType or AARONBOT_MOTIONTYPE_IDLE
end

function ENT:SetupSpeed()
	local speed = 0
	if self:IsCrouching() then
		speed = self:ShouldWalk() and self.WalkSpeed or self.CrouchSpeed
	else
		if self:ShouldRun() then
			speed = self.RunSpeed
		elseif self:ShouldWalk() then
			speed = self.WalkSpeed
		else
			speed = self.MoveSpeed
		end
	end
	speed = self:RunTask("ModifyMovementSpeed", speed) or speed
	self.loco:SetDesiredSpeed(speed)
	self.m_Speed = speed
end

function ENT:GetCurrentSpeed()
	return self.loco:GetVelocity():Length2D()
end

function ENT:GetDesiredSpeed()
	return self.m_Speed or 0
end

function ENT:IsMoving()
	return self:GetCurrentSpeed() > 0.1
end
