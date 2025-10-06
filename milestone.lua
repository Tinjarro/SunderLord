-- milestone.lua (Turtle/1.12 safe)
-- Commands: /sundermilestone on|off|test|tick <5-60>|status

local ADDON_NAME = "SunderLord"
local Milestone = {}
Milestone.fired = {}   -- session "already announced": fired[playerName][threshold] = true
Milestone._dirty = {}  -- names queued for next timer sweep
Milestone._last  = {}  -- last hits we were told per player

-- 5.0-safe length helper (avoid '#' operator)
local function tbl_len(t)
  if type(t) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- =========================
-- SavedVariables (migration-safe)
-- =========================
-- Root from .toc: SunderLordDB
local function DB()
  SunderLordDB = SunderLordDB or {}
  local d = SunderLordDB.milestone

  -- Migrate legacy non-table values (e.g., "on"/"off", true/false, numbers)
  if type(d) ~= "table" then
    local enabled
    if d == "off" or d == 0 or d == false then
      enabled = false
    elseif d == "on" or d == 1 or d == true then
      enabled = true
    else
      enabled = true -- default ON
    end
    d = { enabled = enabled }
    SunderLordDB.milestone = d
  end

  if d.enabled == nil then d.enabled = true end
  if d.tick    == nil then d.tick    = 10   end   -- default: 10 seconds
  return d
end

-- ============= utils =============
local function trim(s) s = s or ""; s = string.gsub(s, "^%s+", ""); s = string.gsub(s, "%s+$", ""); return s end

-- =================
-- MESSAGE POOLS

-- New: POOL_150 (warming up, still humble/brag lite)
local POOL_150 = {
  "%s hits 150 Sunders, consistency unlocked.",
  "150 Sunders for %s, the tank exhales a little.",
  "%s at 150 Sunders, this is an actual habit now.",
  "%s reached 150 Sunders, raid leaders nod in approving spreadsheets.",
  "%s posts 150 Sunders, armor files for a restraining order.",
  "One hundred fifty for %s, not glamorous, just correct.",
  "%s clocks 150 Sunders, healers appreciate the reduced incoming pain.",
  "%s at 150 Sunders, the sunder key is officially worn in.",
  "150 Sunders recorded by %s, dependable is the new exciting.",
  "%s reaches 150 Sunders, the debuff timer thanks you personally.",
  "%s logged 150 Sunders, snacks remain uneaten, work gets done.",
  "At 150 Sunders, %s proves repetition is a feature.",
  "%s marks 150 Sunders, the boss's AC rating weeps softly.",
  "%s at 150 Sunders, the fundamentals are fundamental.",
  "150 Sunders for %s, professional-grade button pressing.",
  "%s hit 150 Sunders, this is either dedication or a very sticky key.",
  "%s crests 150 Sunders, the raid notices and so does the repair bill.",
  "%s notches 150 Sunders, momentum achieved.",
  "%s crosses 150 Sunders, this is the way.",
  "%s tallies 150 Sunders; we like where this is going.",
}



local POOL_50 = {
  "%s hit 50 Sunders, turns out that button wasn't decorative after all.",
  "%s reached 50 Sunders, we knew you had it in you, eventually.",
  "%s officially found the Sunder key, repeatedly, 50 times.",
  "%s at 50 Sunders, slow clap, but a clap nonetheless.",
  "50 Sunders. Somewhere, a sunder dummy sheds a tear of pride for %s.",
  "%s at 50 Sunders, and yes, we can confirm the ability still works.",
  "%s, pressing Sunder so you do not have to, at least 50 times.",
  "Congratulations %s on 50 Sunders, that ability missing error must be long gone.",
  "50 Sunders for %s, the bar icon is glowing with validation.",
  "%s hit 50 Sunders, the crowd yawns, but appreciatively.",
  "It only took 50 Sunders for us to believe %s had it bound.",
  "%s at 50 Sunders achieved, applause, but politely restrained.",
  "%s hit 50 Sunders, noted.",
  "50 Sunders recorded by %s, try not to strain yourself.",
  "%s reached 50 Sunders, clearly that sunder button does in fact exist on the bar.",
  "%s hits 50 Sunders, fundamentals unlocked.",
  "50 Sunders for %s, we call that showing up.",
  "%s at 50 Sunders, armor notices, barely, but it notices.",
  "%s reaches 50 Sunders; somewhere a raid lead stops sighing.",
  "%s logged 50 Sunders; consistent is sexy.",
  "50 Sunders recorded for %s, the debuff is feeling supported.",
  "%s clocks 50 Sunders; tiny violins play a proud tune.",
  "%s hit 50 Sunders, the spreadsheet smiles politely.",
  "At 50 Sunders, %s is now legally a Sunderer.",
  "%s at 50 Sunders; the keybind is officially real.",
  "%s made it to 50 Sunders; guild insurance premiums decline 0.1%.",
  "50 Sunders by %s; the boss's armor files a complaint.",
  "%s at 50 Sunders, the tank nods without looking back.",
  "%s reaches 50 Sunders, the macro works and so do you.",
  "%s posts 50 Sunders; clean, quiet, correct.",
  "%s taps 50 Sunders; that's the stuff.",
  "%s with 50 Sunders; we appreciate your service.",
  "%s delivers 50 Sunders; we love a reliable adult.",
  "%s checks in 50 Sunders; attendance marked.",
  "%s completes 50 Sunders; the golf clap has layers.",
  "%s hits 50 Sunders; the anvil gives a respectful ping.",
  "50 Sunders for %s; the repair vendor cracks a tiny smile.",
  "%s reaches 50 Sunders; the raid leader underlines your name once.",
  "50 Sunders for %s; fresh armor shavings on the floor.",
  "%s spends rage on 50 Sunders; approved by accounting.",
  "%s puts up 50 Sunders; durability checks out.",
  "%s hits 50 Sunders; add one tiny star to the clipboard.",
  "%s records 50 Sunders; the guild bank labels you \"useful.\"",
  "%s lands 50 Sunders; the debuff cap sends a thank-you note.",
  "%s hits 50 Sunders; the shield creaks in acknowledgment.",
  "%s dials up 50 Sunders; form, fit, function.",
  "%s reaches 50 Sunders; your bar key survives the ordeal.",
}


local POOL_150 = {
  "%s clocks 150 Sunders; blacksmiths light a candle in concern.",
  "150 Sunders for %s; healers unclench by two percent.",
  "150 Sunders for %s; the boss adds you to enemies list, page one.",
  "%s dials up 150 Sunders; pull timers look shorter already.",
  "%s completes 150 Sunders; fundamentals with a little swagger.",
  "%s reached 150 Sunders, and somewhere a bard begins writing a song.",
  "%s pressed Sunder 250 times, and the server didn't crash, miracles happen.",
  "%s has achieved 150 Sunders, shattering all known records of button loyalty.",
  "150 Sunders, one warrior, truly Azeroth's greatest love story starring %s.",
  "%s has struck 150 Sunders, the spirits of warriors past nod in approval.",
  "%s at 150 Sunders, a sundering master by any reasonable measure.",
  "150 Sunders achieved, %s now wears the title SunderApprentice.",
  "%s at 150 Sunders, armor yields on principle.",
  "150 Sunders recorded, mastery acknowledged for %s, objections denied.",
  "%s reaches 150 Sunders, the anvil nods, the shield sighs.",
  "150 Sunders complete, %s instructs the boss on proper posture.",
  "%s at 150 Sunders, the spellbook consults him now.",
  "150 Sunders logged, %s sets policy on armor integrity.",
  "%s crosses 150 Sunders, mastery confirmed, humility optional.",
  "150 Sunders reached, %s has nothing left to prove, but will.",
  "%s at 150 Sunders; the raid lead stops calling for sunders.",
  "150 Sunders by %s; the combat log asks for a cold towel.",
}


local POOL_300 = {
  "%s has sundered 300 times, the legends now whisper his name with unease.",
  "%s delivered 300 Sunders, the line between warrior and demigod grows thin.",
  "%s at 300 Sunders, blacksmiths retire knowing their craft is obsolete.",
  "%s completed 300 Sunders, Azeroth itself files a complaint for excessive force.",
  "%s has sundered 300 times, the lorekeepers invent a new pantheon seat.",
  "300 Sunders struck by %s, the walls of Blackrock tremble in recognition.",
  "%s at 300 Sunders, armor no longer resists, it simply resigns.",
  "300 Sunders achieved, and still %s hungers, hubris fully justified.",
  "%s has struck 300 Sunders, the ancients of Lordaeron stir uneasily.",
  "300 Sunders done by %s, the raid frames mark him not as DPS, but as inevitability.",
  "%s at 300 Sunders, the anvil cracks, the forge bows, the steel weeps.",
  "300 Sunders tallied for %s, even Ragnaros lowers his hammer in tribute.",
  "%s at 300 Sunders, kings crown him, dragons flee him, healers fear him.",
  "300 Sunders delivered by %s, parchment cannot hold the tale, only song will do.",
  "%s crossed 300 Sunders, the sundering saga is now carved into myth.",
}

local POOL_500 = {
  "%s at 500 Sunders, prophecy fulfilled, destiny reluctantly confirmed.",
  "500 Sunders struck, even the Titans would consult %s for technique.",
  "%s reached 500 Sunders, the bones of ancient dragons shift in fear.",
  "500 Sunders tallied for %s, Azeroth adjusts its axis in resignation.",
  "%s has sundered 500 times, the scrolls of prophecy update mid sentence.",
  "500 Sunders achieved, the Dark Portal wavers under the pressure of %s.",
  "%s at 500 Sunders, the Keepers of Ulduar pretend not to notice.",
  "500 Sunders recorded, the echoes shake Karazhan's forgotten halls for %s.",
  "%s struck 500 Sunders, the shadows of Blackwing Lair bow their heads.",
  "500 Sunders complete, Elune herself sighs in bemused acknowledgment of %s.",
  "%s reached 500 Sunders, even the elements request a brief intermission.",
  "500 Sunders delivered, the libraries of Dalaran reorder themselves around %s.",
  "%s has achieved 500 Sunders, the world tree shivers, unimpressed but wary.",
  "500 Sunders done, the hourglass of Nozdormu skips a beat for %s.",
  "%s crossed 500 Sunders, Azeroth takes note, mostly out of self preservation.",
}

local POOL_600 = {
  "%s at 600 Sunders, the laws of physics quietly resign.",
  "600 Sunders struck, the Twisting Nether files a formal complaint about %s.",
  "%s reached 600 Sunders, the Old Gods consider early retirement.",
  "600 Sunders achieved, the sands of time spill out of Nozdormu's hourglass for %s.",
  "%s at 600 Sunders, even molten iron refuses to harden in protest.",
  "600 Sunders delivered, Azeroth's ley lines reroute themselves to avoid %s.",
  "%s has sundered 600 times, armor no longer breaks, it evaporates.",
  "600 Sunders tallied, the mountains of Dun Morogh bow ever so slightly to %s.",
  "%s at 600 Sunders, the sky flickers as if reconsidering the script.",
  "600 Sunders logged, the whispers of C'Thun are briefly drowned out by %s.",
  "%s crossed 600 Sunders, Stormwind's walls request hazard pay.",
  "600 Sunders recorded, the forges of Blackrock go silent in protest of %s.",
  "%s has struck 600 Sunders, a tremor races across Kalimdor's spine.",
  "600 Sunders complete, even the runes of Naxxramas falter for a moment before %s.",
  "%s at 600 Sunders, reality itself coughs politely and looks away.",
}

local POOL_700 = {
  "%s has reached 700 Sunders, no longer bound by mortal titles, he walks Azeroth as the Lord of Sundering, a force no armor dares defy.",
  "700 Sunders struck, and the echoes crown %s as the Avatar of Broken Steel, a name to be cursed and worshiped in equal measure.",
  "%s at 700 Sunders, the banners of kingdoms fall as he claims the mantle of High Warlord of Ruin, unchallenged and absolute.",
  "700 Sunders achieved, and Azeroth itself bends, for the Herald of Shattered Armor, %s, has stepped beyond the reach of prophecy.",
  "%s has delivered 700 Sunders, the ancient halls resound with his new title, Champion of the Final Sundering.",
  "700 Sunders complete, and in the silence that follows, the world knows its master as %s, the Eternal Sunderer of Ages.",
  "%s at 700 Sunders, even the bravest dragons retreat, for the Throne of Sundering now belongs to him alone.",
  "700 Sunders recorded, the ancients whisper of %s, the one who sunders destiny itself and writes new laws in steel.",
  "%s has struck 700 Sunders, and the forges cool in reverence to the one true Warden of Ruin.",
  "700 Sunders delivered, and with each swing, %s ascends, the Ascendant of Armor's End, feared by kings and gods alike.",
  "%s at 700 Sunders, the scrolls rewrite themselves, naming him the Arbiter of Sundering, sovereign of broken shields.",
  "700 Sunders tallied, and the world quakes at the rise of %s, the Endless Breaker, whose blows mark the end of eras.",
  "%s has reached 700 Sunders, destiny itself kneels before the Blade of Sundering, humbled and undone.",
  "700 Sunders achieved, and the chorus of ages sings the name of %s, the Shatterer of Empires, breaker of all.",
  "%s at 700 Sunders, a legend beyond recounting, crowned as the Sundermaster Eternal, whose will no shield survives.",
}

local POOL_800 = {
  "%s has reached 800 Sunders. No scroll, no library, no bard could ever hope to capture the breadth of his strikes. History itself stops at this page, for nothing written beyond could compare.",
  "800 Sunders achieved. The thrones of men lie vacant, the halls of kings fall silent, and even the Titans bow their heads. In this age, %s does not play the role of warrior, he plays the role of ending.",
  "%s at 800 Sunders. The oceans still, the mountains wait, and the skies part as if to witness. Mortals can only whisper his name, for he now speaks with the voice of ruin itself.",
  "800 Sunders delivered. Shields no longer break, they choose not to exist at all. %s walks beyond prophecy, carrying with him the silence of all things shattered.",
  "%s has struck 800 Sunders. In that moment, Azeroth itself shudders, not in fear but in recognition of its new master. The age of warriors is over, and only his legend remains.",
  "800 Sunders complete. The walls of Stormwind, the gates of Orgrimmar, the towers of Dalaran, all tremble at the thought of another swing. %s needs no kingdom, for the world itself kneels.",
  "%s reached 800 Sunders. The ancients of Lordaeron rise from their rest, not to fight but to bear witness. From this day forth, no tale can be told without his name carved across it.",
  "800 Sunders tallied. The sundering is no longer an act, but a law of existence. %s speaks, and armor obeys, stone cracks, and time itself yields.",
  "%s at 800 Sunders. The forge is cold, the anvil shattered, and the song of steel replaced by silence. Even gods grow quiet, for they know the final blow has fallen.",
  "800 Sunders achieved. There is no applause, no cheer, no rival, only the echo of eternity breaking. %s does not claim victory, for there is nothing left to claim.",
}

local POOL_1000 = {
  "1000 Sunders; the count is complete, the armor yields, the raid bears witness. By right of steel and stubbornness, %s is named Sunder Lord.",
  "1000 Sunders; metal thins, shields confess, even the anvil nods and steps aside. What began as habit finished as craft; %s is Sunder Lord.",
  "1000 Sunders; the raid stops asking, the boss stops pretending, the record stands. Patient, precise, relentless; %s ascends as Sunder Lord.",
  "1000 Sunders; a milestone, a verdict, a title earned. Pull after pull the debuff held, the plan worked; %s is Sunder Lord.",
  "1000 Sunders; the counter rolls and the room finally smiles. Quiet excellence made loud results; %s takes the name Sunder Lord.",
}


local THRESH_ACTIVE = {50,150,300,500,600,700,800,1000}
local TIER_BY_INDEX = {50,150,300,500,600,700,800,1000}

local POOLS_BY_TIER = {
  [50] = POOL_50,
  [150] = POOL_150,
  [50]  = POOL_50,
  [150]  = POOL_150,
  [300]  = POOL_300,
  [500]  = POOL_500,
  [600]  = POOL_600,
  [700]  = POOL_700,
  [800] = POOL_800,
  [1000] = POOL_1000,
}

-- ==== announcement queue (chat-throttle safe, 1.12-friendly) ====
local AnnQ = { q = {}, interval = 0.25, nextAt = 0 }
local AnnF = CreateFrame("Frame"); AnnF:Hide()

local function __sl_safe_send(msg)
  -- Try raid/party; else print locally
  local ok = true
  if (GetNumRaidMembers() or 0) > 0 then
    ok = pcall(SendChatMessage, msg, "YELL")  -- your original choice
  elseif (GetNumPartyMembers() or 0) > 0 then
    ok = pcall(SendChatMessage, msg, "PARTY")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00"..msg.."|r")
    return
  end
  if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00"..msg.."|r") end
end

AnnF:SetScript("OnUpdate", function()
  local now = GetTime() or 0
  if now < (AnnQ.nextAt or 0) then return end
  local msg = table.remove(AnnQ.q, 1)
  if not msg then AnnF:Hide(); return end
  AnnQ.nextAt = now + (AnnQ.interval or 0.25)
  __sl_safe_send(msg)
end)

local function Announce(msg)
  if not msg or msg == "" then return end
  table.insert(AnnQ.q, msg)
  if not AnnF:IsShown() then AnnF:Show() end
end

function Milestone:Rearm()
  Milestone.fired = {}
  Milestone._dirty = {}
  Milestone._last = {}
end

-- random pick without '#'
local function pick(tbl)
  local n = tbl_len(tbl)
  if n == 0 then return nil end
  return tbl[math.random(1, n)]
end

-- ensure per-player fired map
local function ensureFiredFor(name)
  if not name or name == "" then name = "Unknown" end
  if not Milestone.fired[name] then Milestone.fired[name] = {} end
  return Milestone.fired[name], name
end

-- ========= core evaluation (single player) =========
function Milestone:Check(hits, playerName)
  if not DB().enabled then return end
  if type(hits) ~= "number" or hits < 1 then return end
  local firedFor, who = ensureFiredFor(playerName)

  -- 5.0-safe array loop
  local i, cnt = 1, table.getn and table.getn(THRESH_ACTIVE) or 0
  while i <= cnt do
    local threshold = THRESH_ACTIVE[i]
    if hits >= threshold and not firedFor[threshold] then
      firedFor[threshold] = true
      local tier = TIER_BY_INDEX[i]
      local pool = POOLS_BY_TIER[tier]
      local msg = pool and pick(pool)
      if msg then Announce(string.format(msg, who)) end
    end
    i = i + 1
  end
end

-- ========= timer sweep of dirty names =========
local function sweepDirty()
  if not next(Milestone._dirty) then return end
  local dirty = Milestone._dirty
  Milestone._dirty = {}
  for name in pairs(dirty) do
    local hits = Milestone._last[name]
    if type(hits) == "number" and hits > 0 then
      Milestone:Check(hits, name)
    end
  end
end

-- ========= public hook from SunderLord =========
-- Accepts (name, hits) OR (hits, name) OR (table {name=..., hits=...})
local function normalize(a, b)
  local name, hits
  if type(a) == "string" and type(b) == "number" then
    name, hits = a, b
  elseif type(a) == "number" and (type(b) == "string" or b == nil) then
    name, hits = b or (UnitName("player") or "Unknown"), a
  elseif type(a) == "table" and a then
    name = a.name or a.player or a.owner or (UnitName("player") or "Unknown")
    hits = a.hits or a.count or 0
  else
    name = UnitName("player") or "Unknown"
    hits = tonumber(a) or tonumber(b) or 0
  end
  return name, tonumber(hits) or 0
end

function SunderLord_MilestoneCheck(a, b)
  local name, hits = normalize(a, b)
  Milestone._last[name] = hits      -- cache latest hits
  Milestone._dirty[name] = true     -- mark for timer sweep
end

-- session rearm (debug)
function SunderLord_MilestoneRearm()
  Milestone:Rearm()
end

-- ========= slash =========
SLASH_SUNDERMILESTONE1 = "/sundermilestone"
SlashCmdList["SUNDERMILESTONE"] = function(msg)
  local raw = trim(msg or "")
  local sp = string.find(raw, " ")
  local cmd, rest
  if sp then
    cmd  = string.lower(string.sub(raw, 1, sp-1))
    rest = trim(string.sub(raw, sp+1))
  else
    cmd  = string.lower(raw)
    rest = ""
  end

  local db = DB()
  if cmd == "on" then
    db.enabled = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Sunder milestone enabled.|r")
  elseif cmd == "off" then
    db.enabled = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Sunder milestone disabled.|r")
  elseif cmd == "test" then
    -- keep your original quick demo; leaves timer behavior intact
    local me = UnitName("player") or "Unknown"
    local other = me .. "-Alt"
    Milestone.fired[me] = {}; Milestone.fired[other] = {}
    local i, cnt = 1, table.getn and table.getn(THRESH_ACTIVE) or 0
    while i <= cnt do
      -- feed "hits" via our public hook; timer will announce on next sweep
      SunderLord_MilestoneCheck(me, i)
      SunderLord_MilestoneCheck(other, i)
      i = i + 1
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff88Milestone test queued; will announce on the ticker.|r")
  elseif cmd == "tick" then
    local sec = tonumber(rest)
    if sec and sec >= 5 and sec <= 60 then
      db.tick = math.floor(sec + 0.5)
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff88Milestone tick set to "..db.tick.."s.|r")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff88Usage: /sundermilestone tick <seconds 5-60>|r")
    end
  elseif cmd == "status" or cmd == "" then
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffff88Milestone %s, tick %ds.|r",
      (db.enabled and "enabled" or "disabled"), db.tick or 10))
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff88Usage: /sundermilestone on|off|test|tick <5-60>|status|r")
  end
end

-- ========= init + timer =========
local function startTicker()
  if Milestone._ticker then return end
  local f = CreateFrame("Frame")
  local acc = 0
  f:SetScript("OnUpdate", function()
    if not DB().enabled then return end
    acc = acc + (arg1 or 0)  -- Vanilla: arg1 = elapsed seconds
    local tick = (SunderLordDB and SunderLordDB.milestone and SunderLordDB.milestone.tick) or 10
    if acc >= tick then
      acc = 0
      sweepDirty()
    end
  end)
  Milestone._ticker = f
end

-- (Optional) On login, mark already-crossed thresholds as fired so we don't replay old ones.
local function PullSyncFromSunderLord()
  local map
  if type(SunderLord_GetAllAttempts) == "function" then
    map = SunderLord_GetAllAttempts()
  elseif type(SunderLord_GetAllHits) == "function" then
    map = SunderLord_GetAllHits()
  else
    return
  end
  if type(map) ~= "table" then return end
  for name, hits in pairs(map) do
    local firedFor = ensureFiredFor(name)
    local num = tonumber(hits) or 0
    local i, cnt = 1, table.getn and table.getn(THRESH_ACTIVE) or 0
    while i <= cnt do
      local threshold = THRESH_ACTIVE[i]
      if num >= threshold then
        firedFor[threshold] = true
      end
      i = i + 1
    end
  end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
  DB()
  Milestone:Rearm()
  PullSyncFromSunderLord()
  local t = (GetTime() or 0) * 1000
  math.randomseed(math.mod(t, 2147483647))
  startTicker()
end)
