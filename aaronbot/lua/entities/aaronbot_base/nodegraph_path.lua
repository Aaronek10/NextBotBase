-- AaronBot NodeGraph Path integration

function ENT:NodeGraphPath()
	if AaronBotNodeGraph and AaronBotNodeGraph.Path then
		return AaronBotNodeGraph.Path()
	end
	return Path("Follow")
end

function ENT:SetUseNodeGraph(should)
	self.m_UseNodeGraph = should
end

function ENT:UsingNodeGraph()
	return self.m_UseNodeGraph or false
end
