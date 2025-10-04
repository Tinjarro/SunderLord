SunderLord

Tracks Sunder Armor work in raids and dungeons, shows attempts, applied hits, and reasons for failure per player, posts summaries to chat, and saves progress through reloads, crashes, and graveyard runs. Ships with an optional Milestone helper that announces when you (or others) hit chosen thresholds of applied Sunders.

Compatibility and Requirements
1. Game client: Turtle WoW era, patch 1.12.
2. SuperWoW is required. The addon relies on UNIT_CASTEVENT to see every Sunder attempt, then subtracts misses, dodges, parries, and immunes to calculate applied totals.
- The combat log only shows afflicted lines for the first five stacks, so without SuperWoW you cannot track attempts or total hits reliably.

Verification at Runtime
- You should see attempts increase immediately on any nearby warrior your combat log can see.
- If SUPERWOW_VERSION is missing, SunderLord will still load but will not function correctly.

Files
- SunderLord.toc
- SunderLord.lua
- milestone.lua
- Saved variables:
  - SunderLordDB (account-wide config)
  - SunderLordDBChar (per-character snapshots & totals)

Installation
1. Copy the SunderLord folder into Interface/AddOns.
2. Confirm SunderLord.toc contains:
   ## SavedVariables: SunderLordDB
   ## SavedVariablesPerCharacter: SunderLordDBChar
3. Install and enable SuperWoW.
4. Restart client or run /reload.
5. On first load you will see a hint to type /sunderhelp.

How It Works
1. Attempts come from UNIT_CASTEVENT (spell id + name match).
2. Failures are parsed from combat messages and counted separately: miss, dodge, parry, immune.
3. Applied = attempts − (miss + dodge + parry + immune). Needed because the combat log only shows the first five afflicted lines.
4. A short pairing window matches casts to outcomes to prevent double counting.
5. Per-player stats are tracked locally, sorted, and summarized for posting.

Persistence and Reset
- Snapshots are saved to SunderLordDBChar.snapshot every ~30s, on logout, on leave world, and after first hit.
- Snapshots load at login/reload, so reloads, crashes, and graveyard runs do not wipe progress.
- Lifetime totals are tracked separately in SunderLordDBChar.totals.
- Reset mode is saved in SunderLordDB.config.resetMode. Default is ask.

Reset Modes (/sunderresetmode)
- manual – never auto reset; only /sundersreset.
- auto – reset when entering a new instance key.
- ask – prompt when entering a new instance key; deferred until combat ends; never while ghost. (Default)

Commands
Type /sunderhelp or /slhelp to print this list.

Current Counters
- /sunders – Show current summary.
- /sunderswho – Top 10 per player (current).
- /sundersreset – Reset current counters.
- /sunderpost [where] [N] – Post current top list (auto|raid|party|say|guild). N = number of players.
- /sunderpostwho [where] – Post a single current line.

Totals
- /sunderstotal – Show lifetime totals (never auto resets).
- /sunderresettotal – Wipe lifetime totals.

Reset Mode
- /sunderresetmode manual|auto|ask – Choose reset mode. Default = ask.

Debug
- /slsnap – Show raw snapshot (SavedVariables).

Milestone (optional helper)
- /sundermilestone on – Enable milestone pings.
- /sundermilestone off – Disable milestone pings.
- /sundermilestone status – Show current milestone settings.
- /sundermilestone tick <seconds> – Set timer sweep interval (5–60s; default 10s).
- Thresholds are set in milestone.lua.

Milestone, timer sweep
- Milestone batches work on a short timer instead of firing per-event.
- Default tick: 10 seconds. Range: 5–60 seconds.
- The setting is saved in SunderLordDB.milestone.tick.
- Only the cadence of announcements changes. SunderLord counts and reports (/sunders, /sunderpost, /sunderswho) are unchanged.
- If a threshold is crossed on the boss’s last hit, the next sweep will announce it (prevents end-of-fight misses).
- Each threshold announces once per player per session.

Milestone Thresholds
- Default thresholds: 100, 250, 500, 700, 800, 900, 1000.
- Fires once per threshold per player; deduped for the session.
- Messages are randomized from large themed pools for each tier.
- You can edit milestone.lua to change thresholds or message text.

Output Format
Header: [Sunders] att | applied | miss/dodge/parry/immune | land%
Per player line: Name: attempts | applied | miss/dodge/parry/immune | land%
Short summary: Attempts:X Applied:Y Miss:A Dodge:B Parry:C Immune:D land:Z%
Total summary: [Total] Attempts:X Applied:Y Miss:A Dodge:B Parry:C Immune:D land:Z%

Design Notes
- SuperWoW is mandatory for correct attempt/hit attribution.
- Reset prompts wait until you are out of combat; never shown while ghost.
- Posting validates channels and splits long lines to avoid truncation.
- Immune outcomes are now counted (banished or immune mobs).

Troubleshooting
1. Attempts don’t increase for others: Confirm SuperWoW is loaded and SUPERWOW_VERSION exists.
2. Prompts not appearing in ask mode: Prompts are suppressed while ghost; rez first.
3. Unexpected resets: Switch to manual to test; confirm resets only happen on instance entry.
4. Posting fails: Use a valid destination (auto, raid, party, say, guild).

Version
SunderLord v1.507

Credits
- Tinjarro
- Nerds of a Feather warriors (and the rest of the crew that dealt with my constant spamming)
- SuperWoW authors (cast event API)
- ChatGPT, for doing the boring typing
