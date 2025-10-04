--[[
SunderLord v1.1 (Turtle/1.12 + SuperWoW)


Persistence & UX:
- Per-char SVs (SunderLordDBChar) hold "snapshot" (Current) + "totals" (lifetime).
- Snapshot hydrates via VARIABLES_LOADED, and also on first LOGIN/ENTERING_WORLD if needed.
- No early table creation; DB/CDB bound only when SVs exist.
- Autosave every ~30s and on logout/leave world; extra first-hit flush.
- Reset mode default ASK; prompt deferred out of combat.
- Milestone logic: fires on derived hits (attempts - miss/dodge/parry/immune) per caster.
]]

----------------------------------------------------------------
-- SV handles + runtime
----------------------------------------------------------------
local VER = "1.507"

-- Bind AFTER SVs exist
local DB      -- = SunderLordDB        (account meta/config)
local CDB     -- = SunderLordDBChar    (per-character data)

-- runtime (session-only; we snapshot to CDB.snapshot)
local RUNTIME = {
  counts = { attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0 },
  by     = {}, -- [name] -> {attempts, miss, dodge, parry, _immune_silent}
}

-- state
local SL_HYDRATED = false
local SL_IN_GHOST = false
local SL_FLUSHED_ONCE = false

----------------------------------------------------------------
-- Utils
----------------------------------------------------------------
local function msg(txt) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r "..(txt or "")) end
local function trim(s) if not s then return "" end s=string.gsub(s,"^%s+",""); s=string.gsub(s,"%s+$",""); return s end
local function low(s) return string.lower(s or "") end
local function sanitizeChat(s) s=tostring(s or ""); s=string.gsub(s,"|","||"); return s end

-- Ensure a player row exists in a given table
local function ensurePlayer(t, name)
  if not name or name=="" then name="Unknown" end
  if not t[name] then t[name] = {attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0} end
  return t[name]
end

-- Ensure a player row exists in totals
local function ensureTotalsPlayer(name)
  if not name or name=="" then name="Unknown" end
  local by = CDB.totals.by
  if not by[name] then by[name] = {attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0} end
  return by[name]
end

-- Normalize caster name: if empty/Unknown, assume it's us
local function normalizeCaster(name)
  name = trim(name or "")
  if name == "" or name == "Unknown" then
    local me = UnitName("player")
    if me and me ~= "" then return me end
    return "Unknown"
  end
  return name
end

-- Derived hits = attempts - (miss+dodge+parry+immune)
local function derived_hits(counts)
  local c = type(counts)=="table" and counts or {}
  local h = (c.attempts or 0) - ((c.miss or 0) + (c.dodge or 0) + (c.parry or 0) + (c._immune_silent or 0))
  if h < 0 then h = 0 end
  return h
end

local function applied_pct(counts)
  local a = derived_hits(counts)
  local att = counts and counts.attempts or 0
  return (att > 0) and math.floor((a/att)*100 + 0.5) or 0
end
-- Public: return current sunder "hits" for every tracked warrior.
-- Prefer a direct hits/applied field; otherwise derive from attempts - (miss+dodge+parry+immune).
function SunderLord_GetAllHits()
  local out = {}
  for name, b in pairs(RUNTIME.by or {}) do
    local hits = b.hits or b.applied
    if hits == nil then
      local attempts = tonumber(b.attempts or 0) or 0
      local miss     = tonumber(b.miss or 0) or 0
      local dodge    = tonumber(b.dodge or 0) or 0
      local parry    = tonumber(b.parry or 0) or 0
      local immune   = tonumber(b._immune_silent or 0) or 0
      hits = attempts - (miss + dodge + parry + immune)
    end
    if hits < 0 then hits = 0 end
    out[name] = hits
  end
  return out
end

----------------------------------------------------------------
-- SV binding + defaults + hydration
----------------------------------------------------------------
local function SL_BindSV()
  if not DB or not CDB then
    SunderLordDB     = SunderLordDB     or {}
    SunderLordDBChar = SunderLordDBChar or {}
    DB  = SunderLordDB
    CDB = SunderLordDBChar
  end
end

local function _fill_defaults()
  DB.config = DB.config or {}
  if DB.config.resetMode ~= "manual" and DB.config.resetMode ~= "auto" and DB.config.resetMode ~= "ask" then
    DB.config.resetMode = "ask"
  end
  DB.meta = DB.meta or {}
  DB.meta.instanceKey = DB.meta.instanceKey or ""

  CDB.totals = CDB.totals or {
    counts = {attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0},
    by = {}
  }
  CDB.snapshot = CDB.snapshot or { counts = {}, by = {} }
end

local function load_snapshot_or_fresh()
  local snap = CDB.snapshot
  if not snap then return end
  local sc = snap.counts or {}
  RUNTIME.counts.attempts       = sc.attempts or 0
  RUNTIME.counts.miss           = sc.miss or 0
  RUNTIME.counts.dodge          = sc.dodge or 0
  RUNTIME.counts.parry          = sc.parry or 0
  RUNTIME.counts._immune_silent = sc._immune_silent or 0
  RUNTIME.by = {}
  for name, b in pairs(snap.by or {}) do
    RUNTIME.by[name] = {
      attempts=b.attempts or 0, miss=b.miss or 0, dodge=b.dodge or 0, parry=b.parry or 0,
      _immune_silent=b._immune_silent or 0
    }
  end
end

local function SL_HydrateOnce()
  if SL_HYDRATED then return end
  SL_BindSV()
  _fill_defaults()
  load_snapshot_or_fresh()
  SL_HYDRATED = true
end

----------------------------------------------------------------
-- Snapshot write + reset
----------------------------------------------------------------
local function save_snapshot()
  local snap = { counts={}, by={} }
  local sc, rc = snap.counts, RUNTIME.counts
  sc.attempts, sc.miss, sc.dodge, sc.parry, sc._immune_silent =
    rc.attempts or 0, rc.miss or 0, rc.dodge or 0, rc.parry or 0, rc._immune_silent or 0

  for name, b in pairs(RUNTIME.by) do
    local total = (b.attempts or 0) + (b.miss or 0) + (b.dodge or 0) + (b.parry or 0) + (b._immune_silent or 0)
    if total > 0 then
      snap.by[name] = {
        attempts=b.attempts or 0, miss=b.miss or 0, dodge=b.dodge or 0, parry=b.parry or 0,
        _immune_silent=b._immune_silent or 0
      }
    end
  end
  CDB.snapshot = snap
end

local function hard_reset_current()
  RUNTIME.counts = { attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0 }
  RUNTIME.by = {}
  save_snapshot()
  if SunderLord_Milestone_ResetSession then
    SunderLord_Milestone_ResetSession()
  elseif SunderLord_MilestoneRearm then
    SunderLord_MilestoneRearm()
  end
end

-- periodic autosave
local SL_AutoSave = CreateFrame("Frame")
SL_AutoSave.t, SL_AutoSave.interval = 0, 30
SL_AutoSave:SetScript("OnUpdate", function(self, elapsed)
  elapsed = elapsed or 0
  SL_AutoSave.t = SL_AutoSave.t + elapsed
  if SL_AutoSave.t >= SL_AutoSave.interval then
    SL_AutoSave.t = 0
    if CDB then save_snapshot() end
  end
end)

----------------------------------------------------------------
-- Instance key + reset-mode
----------------------------------------------------------------
local function current_instance_key()
  local zone = GetRealZoneText() or GetZoneText() or "?"
  local sub  = GetSubZoneText() or ""
  local inInst = IsInInstance and IsInInstance() or nil
  return string.format("%s|%s|%s", zone, sub, tostring(inInst or ""))
end

StaticPopupDialogs["SL_RESET_PROMPT"] = {
  text = "SunderLord: New instance detected.\nReset CURRENT counters for this instance?",
  button1 = "Yes",
  button2 = "No",
  OnAccept = function() hard_reset_current(); msg("Current counters reset (ask).") end,
  timeout = 0, whileDead = 1, hideOnEscape = 1,
}

local SL_ResetWait = CreateFrame("Frame")
SL_ResetWait:Hide()
SL_ResetWait:SetScript("OnEvent", function()
  StaticPopup_Show("SL_RESET_PROMPT")
  SL_ResetWait:UnregisterEvent("PLAYER_REGEN_ENABLED")
  SL_ResetWait:Hide()
end)

local function maybe_prompt_reset()
  if UnitAffectingCombat and UnitAffectingCombat("player") then
    SL_ResetWait:RegisterEvent("PLAYER_REGEN_ENABLED")
    SL_ResetWait:Show()
  else
    StaticPopup_Show("SL_RESET_PROMPT")
  end
end

local function handle_zone_transition()
  if not SL_HYDRATED then return end
  if SL_IN_GHOST then
    DB.meta.instanceKey = current_instance_key()
    return
  end
  local key = current_instance_key()
  local inInst = IsInInstance and IsInInstance() or nil
  if DB.config.resetMode == "auto" then
    if inInst and DB.meta.instanceKey ~= key then
      hard_reset_current(); msg("Current counters reset (auto).")
    end
  elseif DB.config.resetMode == "ask" then
    if inInst and DB.meta.instanceKey ~= key then
      maybe_prompt_reset()
    end
  end
  DB.meta.instanceKey = key
end

----------------------------------------------------------------
-- Posting helpers
----------------------------------------------------------------
local function PostTo(where, text)
  local ch = low(where or "")
  text = sanitizeChat(text)
  if ch=="raid" then SendChatMessage(text,"RAID")
  elseif ch=="party" then SendChatMessage(text,"PARTY")
  elseif ch=="guild" then SendChatMessage(text,"GUILD")
  elseif ch=="say" then SendChatMessage(text,"SAY")
  elseif ch=="auto" then
    if GetNumRaidMembers()>0 then SendChatMessage(text,"RAID")
    elseif GetNumPartyMembers()>0 then SendChatMessage(text,"PARTY")
    else SendChatMessage(text,"SAY") end
  else
    msg(text)
  end
end

local function PostMany(where, header, lines)
  if (type(lines) ~= "table") then PostTo(where, "No data yet."); return end
  local n = getn(lines)
  if not n or n == 0 then PostTo(where, "No data yet."); return end
  PostTo(where, header)
  for i=1,n do
    local l = tostring(lines[i] or "")
    if string.len(l) > 240 then
      local s = 1
      local L = string.len(l)
      while s <= L do
        PostTo(where, string.sub(l, s, s+239))
        s = s + 240
      end
    else
      PostTo(where, l)
    end
  end
end

----------------------------------------------------------------
-- Summaries
----------------------------------------------------------------
local function BuildOneLine(name, b)
  local c = { attempts=b.attempts or 0, miss=b.miss or 0, dodge=b.dodge or 0, parry=b.parry or 0, _immune_silent=b._immune_silent or 0 }
  local a = derived_hits(c)
  local pct = applied_pct(c)
  local imm = c._immune_silent or 0
  return string.format(" - %s: %d | %d | %d/%d/%d/%d | %d%%", name, c.attempts, a, c.miss, c.dodge, c.parry, imm, pct)
end

local function BuildAllLinesCurrent()
  local arr = {}
  for name, b in pairs(RUNTIME.by) do table.insert(arr, {name=name, b=b}) end
  table.sort(arr, function(x,y) return (x.b.attempts or 0) > (y.b.attempts or 0) end)
  local n = getn(arr)
  if not n or n == 0 then return nil, "[Sunders] No per-player data yet." end
  local out = {}
  out[1] = "[Sunders] att | applied | miss/dodge/parry/immune | land%"
  local i = 1
  while i <= n and i <= 10 do
    local r = arr[i]; out[getn(out)+1] = BuildOneLine(r.name, r.b); i = i + 1
  end
  if n > 10 then out[getn(out)+1] = string.format(" ...and %d more", n-10) end
  return out, nil
end

local function ShortSummary()
  local c = RUNTIME.counts
  local a = derived_hits(c)
  local pct = applied_pct(c)
  return string.format("Attempts:%d  Applied:%d  Miss:%d  Dodge:%d  Parry:%d  Immune:%d  land:%d%%",
    c.attempts or 0, a, c.miss or 0, c.dodge or 0, c.parry or 0, c._immune_silent or 0, pct)
end

local function TotalSummary()
  local c = CDB.totals and CDB.totals.counts or {attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0}
  local a = (c.attempts or 0) - ((c.miss or 0)+(c.dodge or 0)+(c.parry or 0)+(c._immune_silent or 0))
  if a < 0 then a = 0 end
  local pct = (c.attempts or 0) > 0 and math.floor((a/(c.attempts or 1))*100 + 0.5) or 0
  return string.format("[Total] Attempts:%d  Applied:%d  Miss:%d  Dodge:%d  Parry:%d  Immune:%d  land:%d%%",
    c.attempts or 0, a, c.miss or 0, c.dodge or 0, c.parry or 0, c._immune_silent or 0, pct)
end

----------------------------------------------------------------
-- Core counting
----------------------------------------------------------------
local function addAttempt(caster)
  caster = normalizeCaster(caster)
  local b = ensurePlayer(RUNTIME.by, caster)
  b.attempts = (b.attempts or 0) + 1
  RUNTIME.counts.attempts = (RUNTIME.counts.attempts or 0) + 1

  -- Totals
  local tb = ensureTotalsPlayer(caster)
  tb.attempts = (tb.attempts or 0) + 1
  CDB.totals.counts.attempts = (CDB.totals.counts.attempts or 0) + 1

  save_snapshot()
  if not SL_FLUSHED_ONCE then SL_FLUSHED_ONCE = true; save_snapshot() end

  -- milestone: feed derived hits for THIS caster
  if SunderLord_MilestoneCheck then
    SunderLord_MilestoneCheck(derived_hits(b) or 0, caster)
  end
end

local function addOutcome(caster, key)
  caster = normalizeCaster(caster)
  local b = ensurePlayer(RUNTIME.by, caster)
  if key == "immune" then
    b._immune_silent = (b._immune_silent or 0) + 1
    RUNTIME.counts._immune_silent = (RUNTIME.counts._immune_silent or 0) + 1
  else
    b[key] = (b[key] or 0) + 1
    RUNTIME.counts[key] = (RUNTIME.counts[key] or 0) + 1
  end

  local tb = ensureTotalsPlayer(caster)
  if key == "immune" then
    tb._immune_silent = (tb._immune_silent or 0) + 1
    CDB.totals.counts._immune_silent = (CDB.totals.counts._immune_silent or 0) + 1
  else
    tb[key] = (tb[key] or 0) + 1
    CDB.totals.counts[key] = (CDB.totals.counts[key] or 0) + 1
  end

  save_snapshot()
  if not SL_FLUSHED_ONCE then SL_FLUSHED_ONCE = true; save_snapshot() end

  if SunderLord_MilestoneCheck then
    SunderLord_MilestoneCheck(derived_hits(b) or 0, caster)
  end
end

-- recent cast/outcome tracking (dupe protection)
local CAST = { window=0.60, last={} }
local OUTR = { window=0.90, last={} }
local function keyCT(c,t) return low(c or "?").."->"..low(t or "?") end
local function noteCast(c,t) if c and t then CAST.last[keyCT(c,t)] = GetTime() end end
local function noteOutcome(c,t) if c and t then OUTR.last[keyCT(c,t)] = GetTime() end end
local function hasRecentCast(c,t) local x=CAST.last[keyCT(c,t)]; return x and (GetTime()-x)<=CAST.window end
local function consumeRecentCast(c,t) CAST.last[keyCT(c,t)] = nil end
local function hasRecentOutcome(c,t) local x=OUTR.last[keyCT(c,t)]; return x and (GetTime()-x)<=OUTR.window end

-- parsing helpers
local function isSunderLine(m) return m and string.find(m,"Sunder Armor",1,true) end
local function isAfflictedLine(m)
  -- Ignore "is afflicted by Sunder Armor (N)" lines; they only show for the first 5 stacks.
  if not m then return false end
  return string.find(m, "is afflicted by Sunder Armor", 1, true) ~= nil
end
local function classifyOutcome(m)
  if not m then return nil end
  if     string.find(m," misses ",1,true) then return "miss"
  elseif string.find(m," was dodged ",1,true) or string.find(m," is dodged ",1,true) then return "dodge"
  elseif string.find(m," was parried ",1,true) or string.find(m," is parried ",1,true) then return "parry"
  elseif string.find(m," is immune to ",1,true) and string.find(m,"Sunder Armor",1,true) then return "immune" end
  return nil
end
local function extractCasterFromLine(txt)
  if txt and string.sub(txt,1,5)=="Your " then return UnitName("player") end
  local _,_,who = string.find(txt or "","^([^']+)'s Sunder Armor"); if who then return trim(who) end
  return UnitName("player") or "Unknown" -- hard fallback
end
local function extractTargetFromLine(txt)
  local _,_,t = string.find(txt or ""," hits ([^%s].-) for "); if t then return trim(t) end
  _,_,t = string.find(txt or ""," by (.+)$"); if t then return trim(t) end
end

local function parseGenericMiss(ev, txt)
  local caster, target
  if ev=="CHAT_MSG_COMBAT_SELF_MISSES" then
    caster=UnitName("player"); local _,_,t = string.find(txt or ""," by (.+)$"); target = t and trim(t) or UnitName("target")
  else
    local _,_,t,c = string.find(txt or "", "^(.+)%s+%a+es%s+([^']+)'s"); if t and c then target=trim(t); caster=trim(c) end
    if not caster then local _,_,c2,t2 = string.find(txt or "", "^([^']+)'s .- was .- by (.+)"); if c2 and t2 then caster=trim(c2); target=trim(t2) end end
  end
  return caster, target
end

local function maybeConsumeGenericOutcome(ev, txt, needle, key)
  if not (ev and string.find(ev,"_MISSES",1,true)) then return false end
  if not string.find(low(txt or ""), needle, 1, true) then return false end
  local caster, target = parseGenericMiss(ev, txt); if not caster or not target then return false end
  if hasRecentCast(caster, target) then addOutcome(caster, key); noteOutcome(caster, target); consumeRecentCast(caster, target); return true end
  return false
end

----------------------------------------------------------------
-- Frame + events
----------------------------------------------------------------
local f=CreateFrame("Frame")
-- chat/combat
f:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
f:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
f:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
f:RegisterEvent("CHAT_MSG_COMBAT_PARTY_MISSES")
f:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_MISSES")
f:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
-- lifecycle
f:RegisterEvent("VARIABLES_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("PLAYER_LEAVING_WORLD")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("UNIT_CASTEVENT")
f:RegisterEvent("PLAYER_DEAD")
f:RegisterEvent("PLAYER_ALIVE")
f:RegisterEvent("PLAYER_UNGHOST")

f:SetScript("OnEvent", function()
  local ev=event

  if ev=="PLAYER_LEAVING_WORLD" or ev=="PLAYER_LOGOUT" then
    SL_BindSV(); if CDB then save_snapshot() end
    return
  end

  if ev=="PLAYER_DEAD" then SL_IN_GHOST = true;  return end
  if ev=="PLAYER_ALIVE" or ev=="PLAYER_UNGHOST" then SL_IN_GHOST = false; return end

  if ev=="VARIABLES_LOADED" then
    SL_HydrateOnce()
    return
  end

  if ev=="PLAYER_LOGIN" then
    SL_HydrateOnce()
    DB.meta.helpShownVer = DB.meta.helpShownVer or ""
    if DB.meta.helpShownVer ~= VER then
      msg("Type /sunderhelp (or /slhelp) to see commands. Reset mode default: ASK.")
      DB.meta.helpShownVer = VER
    end
    DB.meta.instanceKey = DB.meta.instanceKey or current_instance_key()
    return
  end

  if ev=="PLAYER_ENTERING_WORLD" or ev=="ZONE_CHANGED_NEW_AREA" then
    SL_HydrateOnce()
    handle_zone_transition()
    return
  end

  -- SuperWoW cast hook
  if ev=="UNIT_CASTEVENT" and SUPERWOW_VERSION then
    local casterGUID, targetGUID, castType, s4, s5 = arg1, arg2, arg3, arg4, arg5
    local spellId, spellName; if type(s4)=="number" then spellId=s4 end; if type(s4)=="string" then spellName=s4 end
    if not spellName and (type(s5)=="string") then spellName=s5 end
    if not spellId and (type(s5)=="number") then spellId=s5 end
    local casterName = (type(s5)=="string" and s5) or (type(casterGUID)=="string" and UnitName(casterGUID)) or nil
    local targetName = (type(targetGUID)=="string" and UnitName(targetGUID)) or nil
    if not (casterName and targetName) then return end
    casterName = normalizeCaster(casterName)
    local ok=false
    if spellName and string.find(spellName,"Sunder Armor",1,true) then ok=true end
    if not ok and spellId and (spellId==7386 or spellId==7405 or spellId==8380 or spellId==11596 or spellId==11597) then ok=true end
    if ok and (castType and (castType=="CAST" or castType=="CAST_START" or castType=="CAST_SUCCESS" or castType=="SPELL_CAST" or castType=="SPELL_DAMAGE" or castType=="SPELL_AURA_APPLIED")) then
      addAttempt(casterName); noteCast(casterName,targetName)
    end
    return
  end

  -- generic outcomes (miss/dodge/parry via non-spell events)
  local raw=arg1
  if raw then
    if maybeConsumeGenericOutcome(ev, raw, "parry", "parry") then return end
    if maybeConsumeGenericOutcome(ev, raw, "dodge", "dodge") then return end
    if maybeConsumeGenericOutcome(ev, raw, "miss",  "miss" ) then return end
  end

  -- explicit sunder lines (hit or outcome)
  local txt = arg1
  if not (txt and isSunderLine(txt)) then return end

  if isAfflictedLine(txt) then return end

  local caster = normalizeCaster(extractCasterFromLine(txt))
  local target = extractTargetFromLine(txt) or "?"

  local outcome = classifyOutcome(txt)

  if outcome then
    -- MISS / DODGE / PARRY / IMMUNE
    local suppressAttempt = hasRecentCast(caster,target) or hasRecentOutcome(caster,target)
    if outcome=="immune" then addOutcome(caster,"immune") else addOutcome(caster,outcome) end
    noteOutcome(caster,target)
    if hasRecentCast(caster,target) then
      consumeRecentCast(caster,target)
    elseif not suppressAttempt then
      addAttempt(caster)
    end
    return
  end

  -- SUCCESSFUL HIT (no miss/dodge/parry/immune text)
  local suppressAttempt = hasRecentCast(caster,target) or hasRecentOutcome(caster,target)
  noteOutcome(caster,target)
  if hasRecentCast(caster,target) then
    consumeRecentCast(caster,target)
  elseif not suppressAttempt then
    addAttempt(caster)
  end
  return
end)

----------------------------------------------------------------
-- Help / Usage
----------------------------------------------------------------
local function SL_PrintHelp()
  local p = function(t) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r "..t) end
  p("SunderLord commands:")
  p("  /sunders                - Current summary (attempts/applied/miss/dodge/parry/land%).")
  p("  /sunderswho             - Current top-10 by attempts.")
  p("  /sundersreset           - Reset CURRENT counters only.")
  p("  /sunderstotal           - Lifetime TOTAL summary (never auto-resets).")
  p("  /sunderresettotal       - Wipe lifetime TOTAL (manual).")
  p("  /sunderpost [where] [N] - Post current top list: auto|raid|party|say|guild; N=lines.")
  p("  /sunderpostwho <Name> [where] - Post a single current player line.")
  p("  /sunderresetmode <m>    - m = manual | auto | ask (default ask).")
  p("  /slsnap                 - Show snapshot counts (SavedVariables) for debug.")
  p("Milestone (if loaded): /sundermilestone on|off|test")
end

----------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------
SLASH_SL1 = "/sunders"
SlashCmdList["SL"] = function()
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r "..ShortSummary())
end

SLASH_SLWHO1 = "/sunderswho"
SlashCmdList["SLWHO"] = function()
  local lines, nodata = BuildAllLinesCurrent()
  if not lines then DEFAULT_CHAT_FRAME:AddMessage(nodata) return end
  for i=1,getn(lines) do DEFAULT_CHAT_FRAME:AddMessage(lines[i]) end
end

SLASH_SLRESET1 = "/sundersreset"
SlashCmdList["SLRESET"] = function()
  hard_reset_current()
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r Current counters reset.")
end

SLASH_SLTOTAL1 = "/sunderstotal"
SlashCmdList["SLTOTAL"] = function()
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r "..TotalSummary())
end

SLASH_SLRESETTOTAL1 = "/sunderresettotal"
SlashCmdList["SLRESETTOTAL"] = function()
  CDB.totals = { counts = {attempts=0, miss=0, dodge=0, parry=0, _immune_silent=0}, by = {} }
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r Totals cleared.")
end

SLASH_SLPOST1 = "/sunderpost"
SlashCmdList["SLPOST"] = function(arg)
  local a = trim(arg or "")
  local where, rest = "", ""
  if a ~= "" then local _,_,w1,w2=string.find(a,"^(%S+)%s*(.*)$"); where=low(w1 or ""); rest=trim(w2 or "") end
  local lines, nodata = BuildAllLinesCurrent()
  if not lines then PostTo(where, nodata); return end
  local n = tonumber(rest)
  if n and n < getn(lines)-1 then
    local cut = { lines[1] }
    local i = 2; local c = 0
    while i <= getn(lines) and c < n do
      cut[getn(cut)+1] = lines[i]
      i=i+1; c=c+1
    end
    lines = cut
  end
  PostMany(where, lines[1], (function()
    local t = {}
    local i=2; while i<=getn(lines) do t[getn(t)+1] = lines[i]; i=i+1 end
    return t
  end)())
end

SLASH_SLPOSTWHO1 = "/sunderpostwho"
SlashCmdList["SLPOSTWHO"] = function(arg)
  local a = trim(arg or "")
  local name, where = "", ""
  if a == "" then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r Usage: /sunderpostwho <PlayerName> [auto|raid|party|say|guild]"); return end
  local _,_,w1,w2=string.find(a,"^(%S+)%s*(.*)$"); name = w1 or ""; where = low(trim(w2 or ""))
  if name == "" then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r Usage: /sunderpostwho <PlayerName> [auto|raid|party|say|guild]"); return end
  local key
  for n,_ in pairs(RUNTIME.by) do if low(n)==low(name) then key=n; break end end
  if not key then PostTo(where, "[Sunders] No current data for "..(name or "?")); return end
  local header = "[Sunders] att | applied | miss/dodge/parry/immune | land%"
  local line   = BuildOneLine(key, RUNTIME.by[key])
  PostMany(where, header, { line })
end

SLASH_SLRESETMODE1 = "/sunderresetmode"
SlashCmdList["SLRESETMODE"] = function(arg)
  local m = low(trim(arg or ""))
  if m~="manual" and m~="auto" and m~="ask" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r Usage: /sunderresetmode manual|auto|ask  (current: "..(DB and DB.config.resetMode or "ask")..")")
    return
  end
  DB.config.resetMode = m
  DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[SL "..VER.."]|r Reset mode set to: "..m)
end

SLASH_SLSNAP1 = "/slsnap"
SlashCmdList["SLSNAP"] = function()
  SL_BindSV()
  local sc = (CDB and CDB.snapshot) or {}
  local cc = sc.counts or {}
  local players = 0
  if sc.by then for _ in pairs(sc.by) do players = players + 1 end end
  DEFAULT_CHAT_FRAME:AddMessage(string.format(
    "|cff66ccff[SL %s Snap]|r att:%d miss:%d dodge:%d parry:%d imm:%d players:%d hydrated:%s",
    VER, tonumber(cc.attempts or 0), tonumber(cc.miss or 0), tonumber(cc.dodge or 0),
    tonumber(cc.parry or 0), tonumber(cc._immune_silent or 0), players, tostring(SL_HYDRATED)
  ))
end

SLASH_SLHELP1 = "/sunderhelp"
SLASH_SLHELP2 = "/slhelp"
SlashCmdList["SLHELP"] = function() SL_PrintHelp() end