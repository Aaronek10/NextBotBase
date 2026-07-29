local function GetControlledBot(ply)
	local bot = ply:GetDrivingEntity()
	if IsValid(bot) and bot.AaronBot then
		return bot
	end
end

function ENT:IsControlledByPlayer()
	local ply = self:GetControlPlayer()
	if not IsValid(ply) then return false end
	if ply:GetDrivingEntity() != self then
		self:StopControlByPlayer()
		return false
	end
	return true
end

function ENT:StartControlByPlayer(ply)
	self:SetControlPlayer(ply)
	self.m_ControlPlayerOldButtons = 0
	self.m_ControlPlayerButtons = 0
	self:ReloadWeaponData()
	self:RunTask("StartControlByPlayer", ply)
end

function ENT:StopControlByPlayer()
	local ply = self:GetControlPlayer()
	self:SetControlPlayer(NULL)
	self:RunTask("StopControlByPlayer", ply)
end

function ENT:ControlPlayerKeyDown(key)
	return bit.band(self.m_ControlPlayerButtons or 0, key) == key
end

function ENT:ControlPlayerKeyPressed(key)
	return self:ControlPlayerKeyDown(key) and bit.band(self.m_ControlPlayerOldButtons or 0, key) != key
end

hook.Add("PlayerButtonDown", "AaronBotControl", function(ply, btn)
	local bot = GetControlledBot(ply)
	if bot and btn == KEY_G then
		bot:DropWeapon()
	end
end)
