# SunderLord

Tracks Sunder Armor work in raids and dungeons, shows attempts, applied hits, and reasons for failure per player, posts summaries to chat, and saves progress through reloads, crashes, and graveyard runs. Ships with an optional **Milestone** helper that announces when you (or others) hit chosen thresholds of applied Sunders.

## Compatibility and Requirements
1. **Game client:** Turtle WoW era, patch 1.12  
2. **SuperWoW is required.** The addon relies on `UNIT_CASTEVENT` to see every Sunder attempt, then subtracts misses, dodges, parries, and immunes to calculate applied totals.  
   *The combat log only shows afflicted lines for the first five stacks, so without SuperWoW you cannot track attempts or total hits reliably.*

### Verification at Runtime
- You should see attempts increase immediately on any nearby warrior your combat log can see.  
- If `SUPERWOW_VERSION` is missing, SunderLord will still load but will not function correctly.

## Files
- `SunderLord.toc`  
- `SunderLord.lua`  
- `milestone.lua`  
- **Saved variables**
  - `SunderLordDB` (account-wide config)
  - `SunderLordDBChar` (per-character snapshots & totals)

## Installation
1. Copy the **SunderLord** folder into `Interface/AddOns`.
2. Confirm `SunderLord.toc` contains:
