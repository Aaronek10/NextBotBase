function ENT:ModifyPlayerControlHUD(x, y, w, h, chx, chy)
	return self:RunTask("ModifyPlayerControlHUD", x, y, w, h, chx, chy)
end

local function GetControlledBot()
	local bot = LocalPlayer():GetDrivingEntity()
	if IsValid(bot) and bot.AaronBot then
		return bot
	end
end

hook.Add("HUDPaint", "AaronBotControl", function()
	local bot = GetControlledBot()
	if not bot then return end

	local p = bot:WorldSpaceCenter():ToScreen()
	local w, h = 70, 15

	local crosshair = util.TraceLine({
		start = bot:GetShootPos(),
		endpos = bot:GetShootPos() + bot:GetEyeAngles():Forward() * 56756,
		mask = MASK_SHOT,
		filter = function(ent)
			if ent == bot or ent:GetParent() == bot then return false end
			if (bot:GetCustomCollisionCheck() or ent:GetCustomCollisionCheck()) and not gamemode.Call("ShouldCollide", bot, ent) then return false end
			return true
		end
	})

	local chp = crosshair.HitPos:ToScreen()

	if bot:ModifyPlayerControlHUD(p.x, p.y, w, h, chp.x, chp.y) then return end

	surface.SetDrawColor(255, 213, 86)
	surface.DrawRect(chp.x, chp.y, 1, 1)
	surface.DrawRect(chp.x - 10, chp.y, 1, 1)
	surface.DrawRect(chp.x + 10, chp.y, 1, 1)
	surface.DrawRect(chp.x, chp.y - 8, 1, 1)
	surface.DrawRect(chp.x, chp.y + 8, 1, 1)

	local hp = math.max(0, bot:Health())
	local maxhp = bot:GetMaxHealth()
	local hpfr = hp / maxhp

	surface.SetDrawColor(0, 0, 0)
	surface.DrawRect(p.x - w / 2, p.y - h / 2, w, h)
	surface.SetDrawColor(hpfr > 0.5 and Color((1 - (hpfr - 0.5) * 2) * 255, 255, 0) or Color(255, hpfr * 2 * 255, 0))
	surface.DrawRect(p.x - w / 2 + 1, p.y - h / 2 + 1, (w - 2) * hpfr, h - 2)
	draw.SimpleText(math.floor(hp) .. "/" .. maxhp, "BudgetLabel", p.x, p.y, nil, 1, 1)

	if bot:HasWeapon() then
		local wep = bot:GetActiveWeapon()
		draw.DrawText(wep:GetPrintName() .. "\nClip 1: " .. bot:GetWeaponClip1() .. "/" .. bot:GetWeaponMaxClip1() .. "\nClip 2: " .. bot:GetWeaponClip2() .. "/" .. bot:GetWeaponMaxClip2(), "BudgetLabel", p.x, p.y + h / 2 + 10, nil, 1)
	end
end)
