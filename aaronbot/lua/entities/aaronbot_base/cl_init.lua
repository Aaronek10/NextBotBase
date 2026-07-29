include("shared.lua")

function ENT:Initialize()
	self.m_TaskList = {}
	self.m_ActiveTasks = {}
	self.m_TaskCallbacks = {}

	self:SetupTaskList(self.m_TaskList)
	self:SetupTasks()
end

function ENT:Draw()
	self:DrawModel()
	self:RunTask("Draw")
end

function ENT:DrawTranslucent()
	self:Draw()
end

-- Player control client side will be added with playercontrol files
include("tasks.lua")
