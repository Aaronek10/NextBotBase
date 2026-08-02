-- Path following fix
--
-- BUG 1: Soft-commit recomputed path every 0.35s (stutter).
-- BUG 2 (main): ControlPath ended with `return false` while still pathing.
--   Movement tasks do:
--     result = ControlPath()
--     if result then      -- arrived
--     elseif result == false then  -- path failed -> TaskFail + wait
--     end                 -- nil = keep moving
--   Returning false mid-path made the bot fail the task every tick and only
--   walk a tiny step before waiting again ("krok po kroczku").
--   Original SB ANB returns nil (implicit) when still following the path.

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

		local recompute = options.recompute or self.PathRecompute or 5
		if path:GetAge() > recompute and self.loco:IsOnGround() then
			path:ResetAge()
			if not self:ComputePath(pos, options.generator) then
				return false
			end
		end
	end

	-- true = arrived, false = failed, nil = still moving (do NOT return false here)
	if self:MoveAlongPath(lookatgoal) then
		return true
	end
end
