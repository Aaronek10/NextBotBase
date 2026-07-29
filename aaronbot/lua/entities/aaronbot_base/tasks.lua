function ENT:SetupTaskList(list)
end

function ENT:SetupTasks()
end

function ENT:RunTask(event, ...)
	local callbacks = self.m_TaskCallbacks[event]
	if not callbacks or #callbacks == 0 then return end

	local m_ActiveTasks = self.m_ActiveTasks
	local m_TaskList = self.m_TaskList
	local PassedTasks = {}

	local k = 1
	while true do
		local task = callbacks[k]
		if not task then break end

		if PassedTasks[task] then
			k = k + 1
			continue
		end
		PassedTasks[task] = true

		local data = m_ActiveTasks[task]
		local callback = m_TaskList[task][event]

		if callback then
			local args = {callback(self, data, ...)}

			if args[1] != nil then
				if args[2] == nil then
					return args[1]
				else
					return unpack(args)
				end
			end

			if callbacks[k] != task then
				k = k - 1
				while k > 0 do
					local ctask = callbacks[k]
					if ctask == task then break end
					k = k - 1
				end
			end
		end

		k = k + 1
	end
end

function ENT:RunCurrentTask(task, event, ...)
	if not self:IsTaskActive(task) then return end

	local dt = self.m_TaskList[task]
	if not dt or not dt[event] then return end

	local args = {dt[event](self, self.m_ActiveTasks[task], ...)}

	if args[1] != nil then
		if args[2] == nil then
			return args[1]
		else
			return unpack(args)
		end
	end
end

function ENT:PushTask(task)
	local data = self.m_TaskList[task]
	if not data then return end

	for k, v in pairs(data) do
		if not isfunction(v) then continue end
		if not self.m_TaskCallbacks[k] then
			self.m_TaskCallbacks[k] = {}
		end
		self.m_TaskCallbacks[k][#self.m_TaskCallbacks[k] + 1] = task
	end
end

function ENT:PopTask(task)
	for event, callbacks in pairs(self.m_TaskCallbacks) do
		for i = 1, #callbacks do
			if callbacks[i] == task then
				table.remove(callbacks, i)
				break
			end
		end
	end
end

function ENT:StartTask(task, data)
	if self:IsTaskActive(task) then return end
	data = data or {}
	self.m_ActiveTasks[task] = data
	self:PushTask(task)
	self:RunCurrentTask(task, "OnStart")
end

function ENT:TaskComplete(task)
	if not self:IsTaskActive(task) then return end
	self:RunCurrentTask(task, "OnComplete")
	self:RunCurrentTask(task, "OnDelete")
	self.m_ActiveTasks[task] = nil
	self:PopTask(task)
end

function ENT:TaskFail(task)
	if not self:IsTaskActive(task) then return end
	self:RunCurrentTask(task, "OnFail")
	self:RunCurrentTask(task, "OnDelete")
	self.m_ActiveTasks[task] = nil
	self:PopTask(task)
end

function ENT:IsTaskActive(task)
	return self.m_ActiveTasks[task] and true or false
end

function ENT:GetActiveTasks()
	return self.m_ActiveTasks
end
