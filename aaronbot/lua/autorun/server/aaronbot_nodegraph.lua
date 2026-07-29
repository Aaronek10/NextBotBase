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

local GO_NORTH = 0
local GO_EAST = 1
local GO_SOUTH = 2
local GO_WEST = 3
local GO_LADDER_UP = 4
local GO_LADDER_DOWN = 5
local GO_JUMP = 6

local MAX_NODES = 3000
local AI_MAX_NODE_LINKS = 30
local AINET_VERSION_NUMBER = 37
local NO_NODE = -1
local LINK_OFF = 0
local LINK_ON = 1
local bits_LINK_STALE_SUGGESTED = 0x01
local bits_LINK_OFF = 0x02
local bits_HULL_BITS_MASK = 0x000002ff

local Nodes, NodeNum = {}, 0
local EditOps, EditOpsInvert = {}, {}
local NodesPos, NodesLinks = {}, {}
local DynamicLinks = {}
local Hints = {}

local cv_drawnodes = CreateConVar("aaronbot_nodegraph_drawnodes", "0", FCVAR_ARCHIVE)
local cv_drawnodes_hull = CreateConVar("aaronbot_nodegraph_drawnodes_hull", "0", FCVAR_ARCHIVE)
local cv_pathdebug = CreateConVar("aaronbot_nodegraph_pathdebug", "0", FCVAR_ARCHIVE)
local cv_accurate = CreateConVar("aaronbot_nodegraph_accurategetnearestnode", "1", FCVAR_ARCHIVE)
local cv_vischeck = CreateConVar("aaronbot_nodegraph_getnearestnodevischeck", "0", FCVAR_ARCHIVE)
local cv_trivial = CreateConVar("aaronbot_nodegraph_trivialcheck", "1", FCVAR_ARCHIVE)
local cv_trivial_debug = CreateConVar("aaronbot_nodegraph_trivialcheck_debug", "0", FCVAR_ARCHIVE)

local function DevMsg(msg) Msg("AaronBotNodeGraph: ", msg) end
local function ThrowError(msg) error("AaronBotNodeGraph: " .. msg, 2) end
local function AssertValid(self) if not self:IsValid() then ThrowError("Attempt to use " .. tostring(self)) end end

local band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift

local function NewObject(meta)
	local obj = newproxy()
	local data = setmetatable({}, {__index = meta.__index})
	debug.setmetatable(obj, {__newindex = data, __index = data, __tostring = meta.__tostring})
	return obj
end

local function PathCostGenerator(path, from, node, cap, botdata)
	if path.m_customcostgen then
		local success, cost = pcall(path.m_customcostgen, node, from, cap)
		if not success then DevMsg("Path cost generation failed! " .. cost .. "\n") return -1 end
		return tonumber(cost) or -1
	end
	if not from then return 0 end
	local frompos, nodepos = from.m_origin, node.m_origin
	local cost = frompos:Distance(nodepos)
	local z = nodepos.z - frompos.z
	if z < -botdata.deathdrop and band(cap, CAP_MOVE_JUMP) ~= 0 then return -1 end
	if band(cap, CAP_MOVE_CLIMB) ~= 0 then return cost * (z > 0 and 0.5 or 4) end
	if band(cap, CAP_MOVE_JUMP) ~= 0 then
		if z >= botdata.jump then return -1 end
		return cost * 5
	elseif band(cap, bor(CAP_MOVE_GROUND, CAP_MOVE_FLY)) ~= 0 then
		return cost
	end
	return cost * 10
end

local function TrivialPathCheck(start, goal, botdata, tolerance, distlimit)
	local mins, maxs = Vector(botdata.cbounds[1]), botdata.cbounds[2]
	mins.z = mins.z + botdata.step
	local dir = goal - start
	local len = dir:Length()
	local step = maxs.x - mins.x
	if distlimit and len > step * 20 then return false end
	dir:Normalize()
	local mask, filter = botdata.mask, botdata.filter
	local height = Vector(0, 0, botdata.step * 2)
	local tlen = len - (tolerance or 0)
	local result = {}
	local tr = {start = start, endpos = start + dir * math.max(0, tlen), mins = mins, maxs = maxs, mask = mask, filter = filter, output = result}
	util.TraceHull(tr)
	if cv_trivial_debug:GetBool() then
		debugoverlay.SweptBox(start, result.HitPos, mins, maxs, angle_zero, 0.25, result.Fraction < 1 and Color(255, 0, 0) or Color(0, 255, 0))
	end
	if result.Fraction < 1 then return false end
	for i = step, len, step * 1.5 do
		tr.start = start + dir * i
		tr.endpos = tr.start - height
		util.TraceHull(tr)
		if result.Fraction >= 1 then return false end
	end
	tr.start = start
	tr.endpos = start + dir * math.max(0, tlen)
	tr.mins = Vector(botdata.bounds[1])
	tr.maxs = botdata.bounds[2]
	tr.mins.z = tr.mins.z + botdata.step
	util.TraceHull(tr)
	return true, result.Fraction < 1
end

local function GetLinkCapabilities(link, from, to, botdata)
	local hull, duckhull = botdata.hull, botdata.duckhull
	local bcap, movetypes = botdata.cap, link.m_AcceptedMoveTypes
	local cap, duck = band(movetypes[hull], bcap), false
	if cap == 0 then cap, duck = band(movetypes[duckhull], bcap), true end
	if cap == 0 then
		duck = false
		if band(bcap, CAP_MOVE_GROUND) ~= 0 and band(bor(movetypes[hull], movetypes[duckhull]), CAP_MOVE_JUMP) ~= 0 then
			local delta = to.m_origin - from.m_origin
			if delta.z < 0 and delta.z > -botdata.deathdrop then
				local len = math.sqrt(delta.x * delta.x + delta.y * delta.y)
				local ang = math.deg(math.atan(-delta.z / len))
				if ang > 50 then cap, duck = CAP_MOVE_GROUND, band(movetypes[hull], CAP_MOVE_JUMP) == 0 end
			end
		end
	end
	return cap, duck
end

local function GetCapBetweenNodes(from, to, botdata)
	for i = 0, from:_NumLinks() - 1 do
		local link = from:_GetLink(i)
		if (link:SrcNode() == from or link:DestNode() == from) and link:DestNode(from) == to then
			return GetLinkCapabilities(link, from, to, botdata)
		end
	end
end

local function GetCapForOutsideSegment(pos, from, to, goal, botdata)
	local cap, duck = GetCapBetweenNodes(from, to, botdata)
	if band(cap, CAP_MOVE_CLIMB) ~= 0 then
		if botdata.ladder then return end
		return CAP_MOVE_GROUND, duck
	elseif band(cap, CAP_MOVE_JUMP) ~= 0 then
		return CAP_MOVE_GROUND, duck
	elseif band(cap, CAP_MOVE_GROUND) ~= 0 then
		local dist = from:GetOrigin():DistToSqr(to:GetOrigin())
		local range = pos:DistToSqr(goal and from:GetOrigin() or to:GetOrigin())
		if range < dist then return end
	end
	return cap, duck
end

local function TranslateCapToPathSegmentType(cap, duckonly, start, goal)
	if band(cap, CAP_MOVE_JUMP) ~= 0 then return PATH_SEGMENT_MOVETYPE_JUMPING end
	if band(cap, CAP_MOVE_CLIMB) ~= 0 then
		if goal.z ~= start.z then return goal.z > start.z and PATH_SEGMENT_MOVETYPE_LADDERUP or PATH_SEGMENT_MOVETYPE_LADDERDOWN end
	end
	return duckonly and PATH_SEGMENT_MOVETYPE_CROUCHING or PATH_SEGMENT_MOVETYPE_GROUND
end

local function NameMatch(query, name)
	if name == "" then return not query or query == "*" end
	if query == name then return true end
	if not query and not name then return true end
	if query:lower() == name:lower() then return true end
	if query == "*" then return true end
	return false
end

local CAI_Node = {
	_initialize = function(self, index, origin, yaw)
		self.m_yaw = yaw
		self.m_id = index
		self.m_voffset = {}
		for i = 0, NUM_HULLS - 1 do self.m_voffset[i] = 0 end
		self.m_links = {}
		self.m_NumLinks = 0
		self.m_type = NODE_GROUND
		self.m_zone = AI_NODE_ZONE_UNKNOWN
		self.m_info = 0
		self:_SetOrigin(origin)
	end,
	_NumLinks = function(self) AssertValid(self) return self.m_NumLinks end,
	_AddLink = function(self, link)
		AssertValid(self)
		if self.m_NumLinks >= AI_MAX_NODE_LINKS then ThrowError("AddLink: Node " .. self.m_id .. " has too many links") end
		self.m_links[self.m_NumLinks] = link
		self.m_NumLinks = self.m_NumLinks + 1
	end,
	_GetLink = function(self, num) AssertValid(self) return self.m_links[num] end,
	GetOrigin = function(self) AssertValid(self) return Vector(self.m_origin) end,
	GetYaw = function(self) AssertValid(self) return self.m_yaw end,
	GetID = function(self) AssertValid(self) return self.m_id end,
	GetType = function(self) AssertValid(self) return self.m_type end,
	GetInfo = function(self) AssertValid(self) return self.m_info end,
	GetZone = function(self) AssertValid(self) return self.m_zone end,
	GetAdjacentNodes = function(self)
		AssertValid(self)
		local t = {}
		for i = 0, self.m_NumLinks - 1 do
			local link = self.m_links[i]
			local neighbor = link:DestNode()
			if neighbor == self then neighbor = link:SrcNode() end
			t[#t + 1] = neighbor
		end
		return t
	end,
	GetAcceptedMoveTypes = function(self, neighbor)
		AssertValid(self)
		for i = 0, self.m_NumLinks - 1 do
			local link = self.m_links[i]
			if link:SrcNode() == self and link:DestNode() == neighbor or link:SrcNode() == neighbor and link:DestNode() == self then
				local t = {}
				for j = 0, NUM_HULLS - 1 do t[j + 1] = link.m_AcceptedMoveTypes[j] end
				return t
			end
		end
	end,
	IsValid = function(self) return not self.m_Removed end,
	_Remove = function(self)
		AssertValid(self)
		NodesPos[self.m_id] = nil
		NodesLinks[self.m_id] = nil
		for i = 0, self:_NumLinks() - 1 do
			local link = self:_GetLink(i)
			local neighbor = link:DestNode()
			if neighbor == self then neighbor = link:SrcNode() end
			NodesLinks[self.m_id .. "_" .. neighbor:GetID()] = nil
			NodesLinks[neighbor:GetID() .. "_" .. self.m_id] = nil
			for j = 0, neighbor:_NumLinks() - 1 do
				local nlink = neighbor:_GetLink(j)
				if link == nlink then
					for k = j, neighbor:_NumLinks() - 1 do
						neighbor.m_links[k] = Either(k == neighbor:_NumLinks() - 1, nil, neighbor.m_links[k + 1])
					end
					neighbor.m_NumLinks = neighbor.m_NumLinks - 1
					if neighbor:_NumLinks() == 0 then NodesLinks[neighbor:GetID()] = neighbor:GetOrigin() end
					break
				end
			end
		end
		self.m_Removed = true
	end,
	_SetOrigin = function(self, origin)
		self.m_origin = Vector(origin)
		NodesPos[self.m_id] = self.m_origin
		NodesLinks[self.m_id] = self.m_origin
	end,
	_InitPosition = function(self)
		if self.m_type == NODE_CLIMB then
			local normal = -Vector(math.cos(math.rad(self.m_yaw)), math.sin(math.rad(self.m_yaw)))
			local endpos = self.m_origin + normal * 100
			local tr = util.TraceLine({start = self.m_origin, endpos = endpos, mask = MASK_NPCSOLID_BRUSHONLY})
			if tr.StartSolid and not tr.AllSolid then
				local delta = endpos - self.m_origin
				local offset = delta * tr.FractionLeftSolid + delta:GetNormalized() * 5
				self:_SetOrigin(self.m_origin + offset)
				for _, n in ipairs(self:GetAdjacentNodes()) do
					if n.m_type == NODE_CLIMB then n:_SetOrigin(n.m_origin + offset) end
				end
			end
		end
	end,
}

local AaronBotNodeGraphNode = {
	__index = CAI_Node,
	__tostring = function(self)
		return "AaronBotNodeGraphNode [" .. (self:IsValid() and self:GetID() or "NULL") .. "]"
	end,
}
debug.getregistry().AaronBotNodeGraphNode = AaronBotNodeGraphNode
debug.getregistry().SBNodeGraphNode = AaronBotNodeGraphNode

local CAI_Link = {
	_initialize = function(self)
		self.m_info = 0
		self.m_AcceptedMoveTypes = {}
		for i = 0, NUM_HULLS - 1 do self.m_AcceptedMoveTypes[i] = 0 end
	end,
	DestNode = function(self, src) return src == self.dest and self.src or self.dest end,
	SrcNode = function(self) return self.src end,
	DestNodeID = function(self, src) return self:DestNode(src):GetID() end,
	SrcNodeID = function(self) return self.src:GetID() end,
}

local CAI_DynamicLink = {
	_initialize = function(self)
		self.m_SrcEditID = self.dlink:GetInternalVariable("startnode")
		self.m_DestEditID = self.dlink:GetInternalVariable("endnode")
		self.m_SrcID = EditOpsInvert[self.m_SrcEditID] or NO_NODE
		self.m_DestID = EditOpsInvert[self.m_DestEditID] or NO_NODE
		self.m_LinkState = self.dlink:GetInternalVariable("initialstate")
		self.m_LinkType = CAP_MOVE_GROUND
		self.m_AllowUse = self.dlink:GetInternalVariable("AllowUse")
		self.m_InvertAllow = self.dlink:GetInternalVariable("m_bInvertAllow")
		DynamicLinks[self] = true
	end,
	GetSrcNodeID = function(self) return self.m_SrcID end,
	GetDestNodeID = function(self) return self.m_DestID end,
	GetStrAllowUse = function(self) return self.m_AllowUse end,
	GetLinkState = function(self) return self.m_LinkState end,
	GetInvertAllow = function(self) return self.m_InvertAllow end,
	IsValid = function(self) return IsValid(self.dlink) end,
	UpdateState = function(self)
		local state = self.dlink:GetInternalVariable("initialstate")
		if self.m_LinkState ~= state then self.m_LinkState = state self:SetLinkState() end
	end,
	SetLinkState = function(self)
		if self.m_SrcID == NO_NODE or self.m_DestID == NO_NODE then
			DevMsg("Dynamic link at " .. tostring(self.dlink:GetPos()) .. " pointing to invalid node ID!!\n")
			return
		end
		local srcnode = Nodes[self.m_SrcID]
		if srcnode then
			local link = self:FindLink()
			if link then
				link.dlink = self
				if self.m_LinkState == LINK_OFF then
					link.m_info = bor(link.m_info, bits_LINK_OFF)
				else
					link.m_info = band(link.m_info, bnot(bits_LINK_OFF))
				end
			else
				DevMsg("Dynamic Link Error: unable to form between nodes " .. self.m_SrcID .. " and " .. self.m_DestID .. "\n")
			end
		end
	end,
	FindLink = function(self)
		local node = Nodes[self.m_SrcID]
		if node then
			for i = 0, node:_NumLinks() - 1 do
				local link = node:_GetLink(i)
				if link:SrcNodeID() == self.m_SrcID and link:DestNodeID() == self.m_DestID or link:SrcNodeID() == self.m_DestID and link:DestNodeID() == self.m_SrcID then
					return link
				end
			end
		end
	end,
}

local SearchList = {
	_initialize = function(self)
		self.Opened, self.Closed, self.CostSoFar, self.TotalCost = {}, {}, {}, {}
		self.NumOpened = 0
	end,
	IsOpenListEmpty = function(self) return self.NumOpened == 0 end,
	GetCostSoFar = function(self, node) return self.CostSoFar[node] end,
	GetTotalCost = function(self, node) return self.TotalCost[node] end,
	PopOpenList = function(self)
		local node, cost
		for cnode, _ in pairs(self.Opened) do
			local ccost = self.TotalCost[cnode]
			if not cost or ccost < cost then node, cost = cnode, ccost end
		end
		self.Opened[node] = nil
		self.NumOpened = self.NumOpened - 1
		return node
	end,
	AddToClosedList = function(self, node) self.Closed[node] = true end,
	IsOpen = function(self, node) return self.Opened[node] == true end,
	AddToOpenList = function(self, node) self.Opened[node] = true self.NumOpened = self.NumOpened + 1 end,
	IsClosed = function(self, node) return self.Closed[node] == true end,
	SetCostSoFar = function(self, node, cost) self.CostSoFar[node] = cost end,
	SetTotalCost = function(self, node, cost) self.TotalCost[node] = cost end,
	RemoveFromClosedList = function(self, node) end,
}

-- PathFollower continues in next part due to size; core APIs below first for Load

local function new_Node(index, origin, yaw)
	local node = NewObject(AaronBotNodeGraphNode)
	node:_initialize(index, origin, yaw)
	return node
end

local function new_Link()
	local link = NewObject({__index = CAI_Link})
	link:_initialize()
	return link
end

local function new_DynamicLink(dlink)
	local link = NewObject({__index = CAI_DynamicLink})
	link.dlink = dlink
	link:_initialize()
	return link
end

local function CreateNode(origin, yaw)
	if NodeNum >= MAX_NODES then
		DevMsg("ERROR: too many nodes in map, deleting last node.\n")
		Nodes[NodeNum]:_Remove()
	end
	local node = new_Node(NodeNum, origin, yaw)
	Nodes[NodeNum] = node
	NodeNum = NodeNum + 1
	return node
end

local function CreateLink(src, dest)
	if src == dest then DevMsg("CreateLink: Attempted to link a node to itself") return end
	if src:_NumLinks() >= AI_MAX_NODE_LINKS then DevMsg("CreateLink: Node " .. src:GetID() .. " has too many links") return end
	if dest:_NumLinks() >= AI_MAX_NODE_LINKS then DevMsg("CreateLink: Node " .. dest:GetID() .. " has too many links") return end
	local link = new_Link()
	link.src = src
	link.dest = dest
	src:_AddLink(link)
	dest:_AddLink(link)
	local center = (src:GetOrigin() + dest:GetOrigin()) / 2
	NodesLinks[src:GetID() .. "_" .. dest:GetID()] = {src:GetID(), dest:GetID(), center, src:GetOrigin():DistToSqr(center)}
	return link
end

function Load()
	local filename = "maps/graphs/" .. game.GetMap() .. ".ain"
	DevMsg("Loading NodeGraph from " .. filename .. " ...\n")
	local f = file.Open(filename, "rb", "GAME")
	if not f then DevMsg("Couldn't read " .. filename .. "!\n") return false end
	if f:Read(3) == "Ver" then
		DevMsg("AI node graph " .. filename .. " is out of date (old structure)\n")
		f:Close()
		return false
	end
	DevMsg("Passed first ver check\n")
	f:Seek(0)
	local aiver = f:ReadLong()
	DevMsg("Got version " .. aiver .. "\n")
	if aiver ~= AINET_VERSION_NUMBER then
		DevMsg("AI node graph " .. filename .. " is out of date\n")
		f:Close()
		return false
	end
	local mapver = f:ReadLong()
	DevMsg("Map version " .. mapver .. "\n")
	DevMsg("Done version checks\n")
	local numNodes = f:ReadLong()
	if numNodes < 0 or numNodes > MAX_NODES then
		DevMsg("AI node graph " .. filename .. " is corrupt (numNodes: " .. numNodes .. ")\n")
		f:Close()
		return false
	end
	DevMsg("Finishing load\n")
	for i = 0, NodeNum - 1 do Nodes[i]:_Remove() end
	Nodes, NodeNum = {}, 0
	for i = 1, numNodes do
		local origin = Vector()
		origin.x = f:ReadFloat()
		origin.y = f:ReadFloat()
		origin.z = f:ReadFloat()
		local yaw = f:ReadFloat()
		local node = CreateNode(origin, yaw)
		for j = 0, NUM_HULLS - 1 do node.m_voffset[j] = f:ReadFloat() end
		node.m_type = f:ReadByte()
		node.m_info = f:ReadUShort()
		node.m_zone = f:ReadShort()
	end
	local numLinks = f:ReadLong()
	for i = 1, numLinks do
		local src = Nodes[f:ReadShort()]
		local dest = Nodes[f:ReadShort()]
		local link = CreateLink(src, dest)
		local movetypes = link and link.m_AcceptedMoveTypes or {}
		for j = 0, NUM_HULLS - 1 do movetypes[j] = f:ReadByte() end
	end
	EditOps, EditOpsInvert = {}, {}
	for i = 0, numNodes - 1 do
		local wcid = f:ReadLong()
		EditOps[i] = wcid
		EditOpsInvert[wcid] = i
		Nodes[i]:_InitPosition()
	end
	local dlinks = 0
	DynamicLinks = {}
	for _, v in ipairs(ents.FindByClass("info_node_link")) do
		local dlink = new_DynamicLink(v)
		if dlink.m_SrcID == NO_NODE or dlink.m_DestID == NO_NODE then
			DynamicLinks[dlink] = nil
			continue
		end
		if band(v:GetSpawnFlags(), bits_HULL_BITS_MASK) ~= 0 then
			local link = dlink:FindLink()
			if not link then
				local srcnode, destnode = Nodes[dlink.m_SrcID], Nodes[dlink.m_DestID]
				if srcnode and destnode then link = CreateLink(srcnode, destnode) end
			end
			if link then
				link.dlink = dlink
				local hullbits = band(v:GetSpawnFlags(), bits_HULL_BITS_MASK)
				for i = 0, NUM_HULLS - 1 do
					if band(hullbits, lshift(1, i)) ~= 0 then link.m_AcceptedMoveTypes[i] = dlink.m_LinkType end
				end
			end
		end
		dlink:SetLinkState()
		dlinks = dlinks + 1
	end
	DevMsg("NodeGraph loaded successfully. Nodes: " .. numNodes .. ", Links: " .. numLinks .. ", Dynamic Links: " .. dlinks .. "\n")
	f:Close()
	return true
end

function GetAllNodes()
	local t = {}
	for i = 0, NodeNum - 1 do t[i + 1] = Nodes[i] end
	return t
end

function GetNodesCount()
	return NodeNum
end

local DistToSqr = debug.getregistry().Vector.DistToSqr
local DistanceToLine = util.DistanceToLine

local function VisibilityCheck(start, endpos, mask)
	local tr = util.TraceLine({start = start, endpos = endpos, mask = mask or MASK_NPCSOLID_BRUSHONLY})
	if not tr.Hit then return true end
	local dist = start:Distance(endpos)
	local trdist = start:Distance(tr.HitPos)
	return dist - trdist < 5
end

function GetNearestNode(pos, visiblepos, mask)
	local curnode, curdist
	if cv_accurate:GetBool() then
		for k, v in pairs(NodesLinks) do
			if istable(v) then
				if DistToSqr(pos, v[3]) > v[4] then continue end
				local start, endpos = NodesPos[v[1]], NodesPos[v[2]]
				local dist, nearpos = DistanceToLine(start, endpos, pos)
				if not curdist or dist * dist < curdist then
					local newnode = DistToSqr(nearpos, start) < DistToSqr(nearpos, endpos) and
						(not visiblepos or VisibilityCheck(visiblepos, start, mask)) and Nodes[v[1]] or
						(not visiblepos or VisibilityCheck(visiblepos, endpos, mask)) and Nodes[v[2]]
					if newnode then curnode, curdist = newnode, dist * dist end
				end
			else
				local dist = DistToSqr(pos, v)
				if (not curdist or dist < curdist) and (not visiblepos or VisibilityCheck(visiblepos, v, mask)) then
					curnode, curdist = Nodes[k], dist
				end
			end
		end
	else
		for i = 0, NodeNum - 1 do
			local dist = DistToSqr(pos, NodesPos[i])
			if (not curdist or dist < curdist) and (not visiblepos or VisibilityCheck(visiblepos, NodesPos[i], mask)) then
				curnode, curdist = Nodes[i], dist
			end
		end
	end
	return curnode
end

function GetNodeByID(id)
	return Nodes[id]
end

function GetEditOps()
	local t = {}
	for i = 1, #EditOps do t[i] = EditOps[i] end
	return t
end

-- Minimal PathFollower: falls back to navmesh Path when nodegraph path needed
-- Full A* PathFollower is included below

local PathFollower
PathFollower = {
	_initialize = function(self)
		self.Segments = {}
		self.NumSegments = 0
		self.Start = Vector()
		self.Goal = Vector()
		self.Length = 0
		self.Tolerance = 25
		self.MinLook = -1
		self.ComputeTime = 0
		self.Valid = false
		self.AvoidTimer = 0
	end,
	_Astar = function(self, start, goal, botdata)
		local from, to
		if cv_vischeck:GetBool() then
			from = GetNearestNode(start, botdata.center)
			to = GetNearestNode(goal, goal + (botdata.center - botdata.pos))
		else
			from, to = GetNearestNode(start), GetNearestNode(goal)
		end
		if not from or not to then return false end
		if from == to then self:_ConstructTrivial(start, goal, from) return true end
		local bot = self.m_Bot
		local nodes = {[from] = "start"}
		local list = NewObject({__index = SearchList})
		list:_initialize()
		list:SetCostSoFar(from, 0)
		list:SetTotalCost(from, from.m_origin:Distance(to.m_origin))
		list:AddToOpenList(from)
		list:AddToClosedList(from)
		while not list:IsOpenListEmpty() do
			local node = list:PopOpenList()
			if node == to then return self:_Construct(nodes, from, to, start, goal, botdata) end
			for i = 0, node.m_NumLinks - 1 do
				local link = node.m_links[i]
				if band(link.m_info, bits_LINK_OFF) ~= 0 then
					local dlink = link.dlink
					if not dlink or not dlink:IsValid() or dlink:GetStrAllowUse() == "" then continue end
					local allowuse = dlink:GetStrAllowUse()
					if dlink:GetInvertAllow() then
						if NameMatch(allowuse, bot:GetName()) or NameMatch(allowuse, bot:GetClass()) then continue end
					else
						if not NameMatch(allowuse, bot:GetName()) and not NameMatch(allowuse, bot:GetClass()) then continue end
					end
				end
				local neighbor = link:DestNode(node)
				local curcap, duck = GetLinkCapabilities(link, node, neighbor, botdata)
				if curcap == 0 then continue end
				local cost = PathCostGenerator(self, node, neighbor, curcap, botdata)
				if cost < 0 then continue end
				local newcost = list:GetCostSoFar(node) + cost
				if not list:IsClosed(neighbor) or newcost < list:GetCostSoFar(neighbor) then
					list:SetCostSoFar(neighbor, newcost)
					list:SetTotalCost(neighbor, newcost + neighbor.m_origin:Distance(to.m_origin))
					if not list:IsOpen(neighbor) then list:AddToOpenList(neighbor) end
					list:AddToClosedList(neighbor)
					nodes[neighbor] = node
				end
			end
		end
		return false
	end,
	_Construct = function(self, nodes, from, to, start, goal, botdata)
		local sequence = {}
		local curnode = to
		while nodes[curnode] do
			local prevnode = nodes[curnode]
			local curid = #sequence + 1
			sequence[curid] = {prevnode:GetOrigin(), curnode:GetOrigin(), prevnode, curnode, GetCapBetweenNodes(prevnode, curnode, botdata)}
			if curnode == to then
				local cap, duck = GetCapForOutsideSegment(goal, prevnode, curnode, true, botdata)
				if not cap then
					sequence[curid][2] = goal
					sequence[curid][4] = nil
				else
					sequence[curid + 1] = sequence[curid]
					sequence[curid] = {curnode:GetOrigin(), goal, curnode, nil, cap, duck}
					curid = curid + 1
				end
			end
			if prevnode == from then
				local cap, duck = GetCapForOutsideSegment(start, prevnode, curnode, false, botdata)
				if not cap then sequence[curid][1] = start
				else sequence[curid + 1] = {start, prevnode:GetOrigin(), nil, prevnode, cap, duck} end
				break
			end
			curnode = prevnode
		end
		self.Segments, self.NumSegments, self.Length = {}, 0, 0
		local prevsegment
		for i = #sequence, 1, -1 do
			local data = sequence[i]
			local cn = data[3] or data[4]
			local movetype = TranslateCapToPathSegmentType(data[5], data[6], data[1], data[2])
			prevsegment = self:_InsertSegment(data[1], data[2], cn, movetype, prevsegment)
		end
		self.CurSegmentID = 0
		self.CurSegment = self.Segments[0]
		self.Valid = true
		self:ResetAge()
		return true
	end,
	_BuildPath = function(self, bot)
		self.m_Bot = bot
		local botdata = {
			pos = bot:GetPos(), center = bot:WorldSpaceCenter(), cap = bot:CapabilitiesGet(),
			hull = bot:GetHullType(), duckhull = bot:GetDuckHullType(), mask = bot:GetSolidMask(),
			step = bot.loco:GetStepHeight(), jump = bot.loco:GetJumpHeight(), deathdrop = bot.loco:GetDeathDropHeight(),
			bounds = {Vector(bot.CollisionBounds[1]), Vector(bot.CollisionBounds[2])},
			cbounds = {Vector(bot.CrouchCollisionBounds[1]), Vector(bot.CrouchCollisionBounds[2])},
			ladder = bot.m_Ladder, filter = bot:GetChildren(),
		}
		botdata.filter[#botdata.filter + 1] = bot
		local trivial, duckonly = TrivialPathCheck(self.Start, self.Goal, botdata, bot.PathGoalToleranceFinal, true)
		if trivial then self:_ConstructTrivial(self.Start, self.Goal, GetNearestNode(self.Start, botdata.center), duckonly) return true end
		return self:_Astar(self.Start, self.Goal, botdata)
	end,
	_ConstructTrivial = function(self, startpos, endpos, node, duckonly)
		self.Segments, self.NumSegments, self.Length = {}, 0, 0
		self:_InsertSegment(startpos, endpos, node, duckonly and PATH_SEGMENT_MOVETYPE_CROUCHING or PATH_SEGMENT_MOVETYPE_GROUND)
		self.CurSegmentID = 0
		self.CurSegment = self.Segments[0]
		self.Valid = true
		self:ResetAge()
	end,
	_InsertSegment = function(self, startpos, endpos, node, movetype, prevsegment)
		local dir = endpos - startpos
		local length = dir:Length()
		dir:Normalize()
		local segment = {area = node, pos = endpos, length = length, forward = dir, type = movetype, curvature = 0}
		if movetype == PATH_SEGMENT_MOVETYPE_GROUND or movetype == PATH_SEGMENT_MOVETYPE_CROUCHING then
			local yaw = math.atan2(dir.x, -dir.y)
			if yaw >= -45 and yaw < 45 then segment.how = GO_NORTH
			elseif yaw >= 45 and yaw < 135 then segment.how = GO_EAST
			elseif yaw >= 135 or yaw < -135 then segment.how = GO_SOUTH
			elseif yaw >= -135 and yaw < -45 then segment.how = GO_WEST end
		elseif movetype == PATH_SEGMENT_MOVETYPE_JUMPING or movetype == PATH_SEGMENT_MOVETYPE_JUMPINGGAP then
			segment.how = GO_JUMP
		elseif movetype == PATH_SEGMENT_MOVETYPE_LADDERUP then segment.how = GO_LADDER_UP
		elseif movetype == PATH_SEGMENT_MOVETYPE_LADDERDOWN then segment.how = GO_LADDER_DOWN
		end
		if prevsegment then prevsegment.curvature = math.acos(dir:Dot(prevsegment.forward)) / math.pi end
		self.Segments[self.NumSegments] = segment
		self.NumSegments = self.NumSegments + 1
		self.Length = self.Length + length
		return segment
	end,
	_UpdateSegment = function(self)
		self.CurSegmentID = self.CurSegmentID + 1
		self.CurSegment = self.Segments[self.CurSegmentID]
		if not self.CurSegment then self:Invalidate() end
	end,
	Compute = function(self, bot, to, customgen)
		self.Start = bot:GetPos()
		self.Goal = Vector(to)
		self.Valid = false
		self.m_customcostgen = customgen
		return self:_BuildPath(bot)
	end,
	FirstSegment = function(self) if not self:IsValid() then return end return self.Segments[0] end,
	GetAge = function(self) return CurTime() - self.ComputeTime end,
	GetAllSegments = function(self)
		if not self:IsValid() then return end
		local t = {}
		for i = 0, self.NumSegments - 1 do t[i + 1] = table.Copy(self.Segments[i]) end
		return t
	end,
	GetCurrentGoal = function(self) if not self:IsValid() then return end return table.Copy(self.CurSegment) end,
	GetEnd = function(self) return Vector(self.Goal) end,
	GetGoalTolerance = function(self) return self.Tolerance end,
	GetLength = function(self) return self.Length end,
	GetMinLookAheadDistance = function(self) return self.MinLook end,
	GetStart = function(self) return Vector(self.Start) end,
	Invalidate = function(self) self.Valid = false end,
	IsValid = function(self) return self.Valid end,
	LastSegment = function(self) if not self:IsValid() then return end return self.Segments[self.NumSegments - 1] end,
	PriorSegment = function(self) if not self:IsValid() then return end return self.Segments[self.CurSegmentID - 1] end,
	NextSegment = function(self) if not self:IsValid() then return end return self.Segments[self.CurSegmentID + 1] end,
	ResetAge = function(self) self.ComputeTime = CurTime() end,
	SetGoalTolerance = function(self, t) self.Tolerance = t end,
	SetMinLookAheadDistance = function(self, d) self.MinLook = d end,
	Update = function(self, bot)
		if not self:IsValid() then return end
		local curpos = bot:GetPos()
		local dist = self:GetGoalTolerance()
		local goal = self.CurSegment
		local goalpos = goal.pos
		if not bot.m_Ladder and math.Distance(curpos.x, curpos.y, goalpos.x, goalpos.y) <= dist then
			self:_UpdateSegment()
			if not self:IsValid() then return end
			goal = self.CurSegment
			goalpos = goal.pos
		end
		if goal.how == GO_LADDER_UP or goal.how == GO_LADDER_DOWN then
			if not bot.m_Ladder then
				if Either(goal.how == GO_LADDER_UP, curpos.z >= goalpos.z - bot.StepHeight, curpos.z <= goalpos.z + bot.StepHeight) then
					self:_UpdateSegment()
					return self:Update(bot)
				else
					local prev = self.Segments[self.CurSegmentID - 1]
					local bottom = goal.how == GO_LADDER_UP and prev or goal
					local top = goal.how == GO_LADDER_UP and goal or prev
					local yaw = math.rad(bottom.area:GetYaw())
					local normal = -Vector(math.cos(yaw), math.sin(yaw), 0)
					bot:AttachToLadder({bottom = bottom.pos, top = top.pos, normal = normal})
					bot:Approach(curpos + Vector(0, 0, goal.how == GO_LADDER_UP and 1 or -1))
				end
			else
				bot:Approach(curpos + Vector(0, 0, goal.how == GO_LADDER_UP and 1 or -1))
			end
		elseif goal.type == PATH_SEGMENT_MOVETYPE_GROUND or goal.type == PATH_SEGMENT_MOVETYPE_CROUCHING then
			bot:Approach(goalpos)
		elseif goal.how == GO_JUMP then
			if bot.loco:IsOnGround() then
				local result = bot:CalcJumpHeightOverObstacles(goalpos)
				if isnumber(result) then bot:JumpToPos(goalpos, result)
				elseif result == true then
					local dir = curpos - goalpos dir.z = 0 dir:Normalize()
					bot:Approach(curpos + dir * 100)
				elseif istable(result) then bot:JumpToPos(result.pos, result.height)
				else bot:JumpToPos(goalpos, bot.MaxJumpToPosHeight) end
			end
		end
		if cv_pathdebug:GetBool() then
			debugoverlay.Cross(goalpos, 5, 0.1, Color(150, 150, 255), true)
			debugoverlay.Line(bot:WorldSpaceCenter(), goalpos, 0.1, Color(255, 255, 0), true)
		end
	end,
}

local AaronBotNodeGraphPathFollower = {
	__index = PathFollower,
	__tostring = function() return "AaronBotNodeGraphPathFollower" end,
}
debug.getregistry().AaronBotNodeGraphPathFollower = AaronBotNodeGraphPathFollower
debug.getregistry().SBNodeGraphPathFollower = AaronBotNodeGraphPathFollower

function Path()
	local path = NewObject(AaronBotNodeGraphPathFollower)
	path:_initialize()
	return path
end

hook.Add("Think", "aaronbot_nodegraph_dlinks", function()
	for link, _ in pairs(DynamicLinks) do
		if not link:IsValid() then DynamicLinks[link] = nil else link:UpdateState() end
	end
end)

timer.Create("aaronbot_nodegraph_drawnodes", 1, 0, function()
	local drawtype = cv_drawnodes:GetInt()
	if drawtype <= 0 then return end
	local mins, maxs = Vector(-5, -5, -5), Vector(5, 5, 5)
	for i = 0, NodeNum - 1 do
		local node = Nodes[i]
		local r, g, b = 0, 255, 100
		if node:GetType() == NODE_AIR then r, g, b = 0, 255, 255
		elseif node:GetType() == NODE_CLIMB then r, g, b = 255, 0, 255
		elseif node:GetType() == NODE_WATER then r, g, b = 0, 0, 255 end
		debugoverlay.Box(node:GetOrigin(), mins, maxs, 1.5, Color(r, g, b, 0))
		for j = 0, node:_NumLinks() - 1 do
			local link = node:_GetLink(j)
			local dest = link:DestNode()
			if dest == node then dest = link:SrcNode() end
			if dest:GetID() < node:GetID() then continue end
			debugoverlay.Line(node:GetOrigin() + vector_up, dest:GetOrigin() + vector_up, 1.5, Color(0, 255, 50), false)
		end
	end
end)

hook.Add("Initialize", "AaronBotNodeGraph", function()
	timer.Simple(5, function()
		if AaronBotNodeGraph and AaronBotNodeGraph.Load then
			AaronBotNodeGraph.Load()
		end
	end)
end)

print("[AaronBot] NodeGraph module loaded (full binary loader + PathFollower)")
