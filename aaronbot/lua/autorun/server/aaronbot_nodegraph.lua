-- AaronBot NodeGraph Module (rebranded from SB Advanced Nextbots)
-- Full port with AaronBot naming for uniformity.

if AaronBotNodeGraph then return end

module("AaronBotNodeGraph", package.seeall)

NODE_ANY = 0
NODE_DELETED = 1
NODE_GROUND = 2
NODE_AIR = 3
NODE_CLIMB = 4
NODE_WATER = 5

AI_NODE_ZONE_UNKNOWN = 0
AI_NODE_ZONE_SOLO = 1
AI_NODE_ZONE_UNIVERSAL = 2
AI_NODE_FIRST_ZONE = 3

PATH_SEGMENT_MOVETYPE_GROUND = 0
PATH_SEGMENT_MOVETYPE_CROUCHING = 1
PATH_SEGMENT_MOVETYPE_JUMPING = 2
PATH_SEGMENT_MOVETYPE_JUMPINGGAP = 3
PATH_SEGMENT_MOVETYPE_LADDERUP = 4
PATH_SEGMENT_MOVETYPE_LADDERDOWN = 5

-- (Full implementation continues - the complete rebranded module will be uploaded in subsequent commits as content is processed)
-- For now this ensures the module exists and Load is available.

local Nodes, NodeNum = {}, 0

function Load()
	print("[AaronBotNodeGraph] Load called - full nodegraph port in progress")
	-- TODO: full binary .ain loader (will be completed in next push)
end

function GetAllNodes()
	return {}
end

function GetNodesCount()
	return NodeNum
end

function GetNearestNode(pos, visiblepos, mask)
	return nil
end

function Path()
	local path = Path("Follow")
	return path
end

hook.Add("Initialize", "AaronBotNodeGraph", function()
	timer.Simple(5, AaronBotNodeGraph.Load)
end)

print("[AaronBot] NodeGraph module loaded (rebranded stub - full port next)")
