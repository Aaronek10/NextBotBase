AddCSLuaFile()

ENT.Base = "aaronbot_soldier_base"
DEFINE_BASECLASS(ENT.Base)

ENT.PrintName = "AaronBot Soldier (Follower)"

list.Set("NPC", "aaronbot_soldier_follower", {
	Name = ENT.PrintName,
	Class = "aaronbot_soldier_follower",
	Category = "AaronBot",
	Weapons = {"weapon_smg1", "weapon_ar2", "weapon_shotgun", "weapon_pistol", "weapon_357", "weapon_crossbow"},
})

if CLIENT then
	language.Add("aaronbot_soldier_follower", "AaronBot Soldier (Follower)")
	return
end

hook.Add("PlayerSpawnedNPC", "aaronbot_soldier_follower", function(ply, npc)
	if npc:GetClass() == "aaronbot_soldier_follower" then
		npc.Target = ply
		npc:SetEntityRelationship(npc.Target, D_LI)
	end
end)

ENT.SpawnHealth = 1000

ENT.Models = {
	"models/player/combine_soldier.mdl",
	"models/player/combine_super_soldier.mdl",
	"models/player/combine_soldier_prisonguard.mdl",
}

function ENT:Initialize()
	BaseClass.Initialize(self)
	self:SetModel(table.Random(self.Models))
	self:SetFriendly(true)
	self:SetClassRelationship("aaronbot_soldier_follower", D_LI)
end
