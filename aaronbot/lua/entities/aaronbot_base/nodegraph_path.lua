-- Thin wrapper; full nodegraph lives in autorun/server (ported later if needed).
-- When UsingNodeGraph() is true, Path methods delegate here.
AaronBotNodeGraph = AaronBotNodeGraph or {}
AaronBotNodeGraph.PATH_SEGMENT_MOVETYPE_CROUCHING = 1

function ENT:NodeGraphPath()
	-- Placeholder: returns standard Path until nodegraph autorun is ported.
	return Path("Follow")
end
