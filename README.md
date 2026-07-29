# AaronBot (NextBotBase)

Rebranded Advanced NextBot base for Garry's Mod.

## Structure

```
aaronbot/
  lua/
    autorun/server/aaronbot_nodegraph.lua
    entities/
      aaronbot_base/     -- full base
      aaronbot_soldier_base.lua
      aaronbot_soldier_friendly.lua
      aaronbot_soldier_hostile.lua
      aaronbot_soldier_follower.lua
    weapons/
      weapon_*_aaronbot.lua
```

## Status

- ✅ Base entity (motion, weapons, enemy, tasks, player control)
- ✅ Soldiers (friendly / hostile / follower)
- ✅ All weapon analogs (`weapon_*_aaronbot`)
- ✅ Legacy `sb_advanced_nextbots/` removed
- ⏳ Full nodegraph `.ain` binary loader (module stub present; uses navmesh by default)

## Author

Aaronek10 — rebrand of Shadow Bonnie (RUS) SB Advanced Nextbots
