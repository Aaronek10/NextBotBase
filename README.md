# AaronBot (NextBotBase)

Rebranded Advanced NextBot base for Garry's Mod.

## Structure

```
aaronbot/
  lua/
    autorun/server/aaronbot_nodegraph.lua   -- full .ain loader + PathFollower
    entities/
      aaronbot_base/
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
- ✅ Full nodegraph binary `.ain` loader + A* PathFollower
- ✅ Legacy `sb_advanced_nextbots/` removed

## ConVars

- `aaronbot_soldier_playerdisposition`
- `aaronbot_soldier_usenodegraph`
- `aaronbot_drawpath`
- `aaronbot_nodegraph_drawnodes`
- `aaronbot_nodegraph_pathdebug`
- `aaronbot_nodegraph_accurategetnearestnode`

## Author

Aaronek10 — rebrand of Shadow Bonnie (RUS) SB Advanced Nextbots
