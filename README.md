# ⛏️ fivesawMiner

> **Full Hypixel Skyblock Mining Bot for NeoScripts** — Commission, Glacial, Route, and Freemine macros.

<div align="center">

![Lua](https://img.shields.io/badge/Lua-5.4-blue?logo=lua&logoColor=white)
![NeoScripts](https://img.shields.io/badge/NeoScripts-1.21.11-green)
![License](https://img.shields.io/badge/license-MIT-orange)
![Build](https://img.shields.io/github/actions/workflow/status/goatdotlol/fivesawMiner/lua-check.yml?label=syntax%20check)

**A complete 1:1 port of MightyMiner v2 to Lua.**
4 macros • 13 failsafes • auto-detection • humanized movement • one file.

</div>

---

## 🎮 Macros

| Macro | Description | States |
|---|---|---|
| ⚒️ **Commission** | Auto-completes Dwarven Mines commissions | Starting → Mining/Slaying → Claiming → Warping |
| 🧊 **Glacial** | Mines glacite veins in Glacite Tunnels | Mining → VeinScan → Pathfinding → Claiming |
| ⛏️ **Mining** | Simple mining loop at current location | BlockMiner loop with auto-restart |
| 🗺️ **Route** | Follows waypoint route + mines at each stop | Moving → Mining → Next Waypoint |

## ✨ Features

### Mining Engine
- 🎯 **28 ore types** — Mithril (gray/green/blue), Titanium, Glacite, Hardstone, Umber, Tungsten, Diamond, Emerald, Gold, and more
- 📊 **Smart block selection** — Cost-based scoring (mining speed × distance × angle change)
- ⚡ **Pickaxe abilities** — Mining Speed Boost, Pickobulus with auto-detection
- 🔄 **Auto mining speed detection** — Reads speed from item lore automatically

### Commission System
- 📋 **Auto commission detection** — Parses tablist for active commissions
- 🏆 **Priority system** — Picks best commission (mining > slayer)
- 🐦 **Dual claiming** — Royal Pigeon or walk-to-emissary
- ⚔️ **Slayer support** — Auto mob killer for Goblin/Glacite Walker commissions
- 🔄 **Full loop** — Claim → get new commission → mine → repeat

### Failsafes (13 Total)
| Failsafe | Trigger |
|---|---|
| 💬 Name Mention | Someone says your name in chat |
| 🌍 World Change | Server sends you to a different world |
| 📦 Item Change | Mining tool disappears from hotbar |
| 👤 Profile Change | SkyBlock profile swap detected |
| 💥 Knockback | Sudden position change (>3 blocks/tick) |
| 🔌 Disconnect | Connection lost (auto-reconnect × 5) |
| 🧱 Bedrock Surround | Surrounded by bedrock (wrong area) |
| 👥 Player Nearby | Non-NPC player within 3 blocks for 3+ sec |
| ☄️ Teleport | Server-forced position change |
| 🔄 Rotation | Server-forced rotation change |
| 🎰 Slot Change | Hotbar slot forcefully changed |
| ☠️ Bad Effect | Harmful potion effects detected |
| 🪨 Bedrock Block | Bedrock appearing where it shouldn't |

### Extras
- ⛽ **Auto Drill Refuel** — Detects low fuel, opens Abiphone → Greatforge → refuels
- 🗺️ **Route System** — Hardcoded defaults + JSON file loader
- 🎨 **ImGui Config** — Full settings panel (press F6)
- 📊 **HUD Overlay** — Uptime, state, commission count, target block
- 🐛 **Debug Renderer** — Target block highlight in-world

## 📥 Installation

1. Download **both files**
2. Drop them in NeoScripts:

```
NeoScripts/
├── libs/
│   └── fivesawUtils.lua     ← pathfinding library
└── scripts/
    └── fivesawMiner.lua     ← this macro
```

3. Launch NeoScripts — press **F6** to configure

> ⚠️ **Requires `fivesawUtils.lua`** — the pathfinding library. Get it from [fivesawUtils](https://github.com/goatdotlol/fivesawUtils).

## 🎮 Usage

### Config Panel (F6)
Press **F6** in-game to open the full config panel:
- Select macro type (Commission/Glacial/Mining/Route)
- Set ore type, mining tool, mining speed
- Toggle auto-detect, pickaxe abilities
- Configure claim method (Pigeon vs Emissary)
- Enable/disable failsafes
- Auto drill refuel settings

### Chat Commands
| Command | Action |
|---|---|
| `#fivesaw` / `#fs` | Toggle macro on/off |
| `#fsstop` | Force stop |
| `#fstype <0-3>` | Set macro (0=Commission, 1=Glacial, 2=Mining, 3=Route) |
| `#fsspeed <n>` | Set mining speed |
| `#fstool <name>` | Set mining tool name |
| `#fsore <0-11>` | Set ore type |
| `#fsroute add` | Add waypoint at current position |
| `#fsroute clear` | Clear custom route |
| `#fsroute load <file>` | Load route from JSON file |
| `#fsdebug` | Toggle debug mode |
| `#fshelp` | Show all commands |

## 🛡️ Anti-Cheat Design

Every interaction is designed to look human:

- **Bézier Curve Rotations** — Cubic Bézier with randomized control points (not linear snapping)
- **Server-Side Rotation** — Uses `setSilentRotation` for legitimate server packets
- **Real Key Presses** — All movement via `input.setPressed*`
- **Humanized Timing** — Rotation time scales with angle, randomized delays
- **Mining Jitter** — Slight random offsets on block targeting
- **Attack Cooldown** — Respects 1.21 combat cooldown for mob killing

## 🏗️ Architecture

```
fivesawMiner.lua (bundled)
├── core         — Clock, GameState, RotationHandler (Bézier), MacroBase
├── block_miner  — 28 MineableBlocks, BlockScanner, BlockMiner state machine
├── utils        — Commission, Failsafes, AutoMobKiller, DrillRefuel, NPC, VeinScanner  
├── macros       — MiningMacro, CommissionMacro, GlacialMacro, RouteMiner
├── route_data   — Default waypoints + JSON loader
└── init         — MacroManager, ImGui, HUD, Commands, Renderer
```

## 📄 Route File Format

Custom routes use simple JSON:
```json
[
  {"x": 100, "y": 64, "z": 200, "name": "Vein 1"},
  {"x": 110, "y": 64, "z": 210, "name": "Vein 2"},
  {"x": 120, "y": 64, "z": 220, "name": "Vein 3"}
]
```

## 📄 License

MIT — Free to use, modify, and distribute.

## 🙏 Credits

- **MightyMiner** by JellyLabScripts — original Java mod this is ported from
- **Baritone** — pathfinding algorithms
- **fivesaw** — Lua port, humanization, anti-cheat design

---

<div align="center">

**Made by [fivesaw](https://github.com/goatdotlol)** ⛏️

*If this helped you, star the repo ⭐*

</div>
