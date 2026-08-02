-- Path following fix: aggressive soft-commit was recomputing the path every 0.35s
-- whenever the current segment was >200u away. That constantly rebuilt the PathFollower
-- and produced the "step by step" stutter with almost no distance covered.
--
-- Loaded after motion.lua from init.lua. Later redefine wins in Lua.

function ENT:ControlPath(lookatgoal)
	if not self:PathIsValid() then return false end

	local path = self:GetPath()
	local pos = self:GetPathPos()
	local options = self.m_PathOptions or {}

	if not self.m_Ladder then
		local range = self:GetRangeSquaredTo(pos)
		local tol = options.tolerance or self.PathGoalTolerance or 25
		local tolFinal = self.PathGoalToleranceFinal or 25

		if range < tol * tol or range < tolFinal * tolFinal then
			path:Invalidate()
			return true
		end

		-- Original SB ANB behaviour: recompute only on age, not every fraction of a second.
		local recompute = options.recompute or self.PathRecompute or 5
		if path:GetAge() > recompute and self.loco:IsOnGround() then
			path:ResetAge()
			if not self:ComputePath(pos, options.generator) then
				return false
			end
		end
	end

	if self:MoveAlongPath(lookatgoal) then return true end
	return false
end
