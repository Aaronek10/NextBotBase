# AaronBot / NextBotBase

Rebranded Advanced NextBot base for Garry's Mod.

## Structure

```
aaronbot/
  lua/
    autorun/server/aaronbot_nodegraph.lua
    entities/
      aaronbot_base/          -- full base (motion, weapons, enemy, tasks, player control)
      aaronbot_soldier_base.lua
      aaronbot_soldier_friendly.lua
      aaronbot_soldier_hostile.lua
      aaronbot_soldier_follower.lua
    weapons/
      weapon_*_aaronbot.lua
```

## Status

- ✅ Base entity fully ported and rebranded
- ✅ Soldiers (base + friendly/hostile/follower)
- ✅ Weapons (pistol, smg1; remaining analogs follow same pattern)
- ⏳ Full nodegraph .ain loader (stub present)
- ⏳ Remaining weapon analogs (ar2, shotgun, 357, crossbow, rpg, crowbar, stunstick)
- ⏳ Remove legacy `sb_advanced_nextbots/` folder

## Author

Aaronek10 (rebrand from Shadow Bonnie RUS SB Advanced Nextbots)
