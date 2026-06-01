-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Dice rolling
-------------------------------------------------------------------------------
--
-- How it works: WoW's /roll only ever produces a plain "Name rolls X (a-b)"
-- system message, with no notion of multiple dice or modifiers. To present a
-- rich roll ("You roll 4 and 6 = 10 (2D6)") we:
--
--   1. Broadcast an addon message describing the *intended* roll (dice count,
--      sides, modifier) to the group.
--   2. Ask the server for the actual random numbers via RandomRoll().
--   3. Hide the raw system roll lines and match them back up with the intent,
--      then print a formatted result.
--
-- Everyone in the group running this addon sees the same nicely formatted line;
-- players without it still see the raw rolls plus an optional <Emberhollow>
-- summary so the roll isn't lost on them.
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

local ROLL_TIMEOUT = 1.5   -- grace period before we give up matching and print the raw roll
local CLEAN_TIME   = 5     -- how long stale roll data lingers before being discarded

-- Build a Lua pattern from the localized "%s rolls %d (%d-%d)" string so we can
-- recognise (and capture) server roll messages in any client language.
-- English result: "(%S+) rolls (%d+) %((%d+)%-(%d+)%)"
local SYSTEM_ROLL_PATTERN = RANDOM_ROLL_RESULT
SYSTEM_ROLL_PATTERN = SYSTEM_ROLL_PATTERN:gsub( "%%s", "(%%S+)" )
SYSTEM_ROLL_PATTERN = SYSTEM_ROLL_PATTERN:gsub( "%%d", "(%%d+)" )
SYSTEM_ROLL_PATTERN = SYSTEM_ROLL_PATTERN:gsub( "%(%(%%d%+%)%-%(%%d%+%)%)", "%%((%%d+)%%-(%%d+)%%)" )
-- (The replacement above collapses the two adjacent "(%d+)" captures that came
--  from "(%d-%d)" back into the parenthesised "(min-max)" form.)

local doingRoll = false   -- true while WE are driving RandomRoll()

local playerServerRolls = {}   -- name -> queue of raw server rolls
local playerRollInfo    = {}   -- name -> queue of intended-roll descriptors

-------------------------------------------------------------------------------
-- Format a dice type, e.g. FormatDiceType( 2, 6, 1 ) -> "2D6+1".
--
local function FormatDiceType( count, sides, mod )
	local dice = "D" .. sides
	if count ~= 1 then
		dice = count .. dice
	end
	if mod > 0 then
		dice = dice .. "+" .. mod
	elseif mod < 0 then
		dice = dice .. mod
	end
	return dice
end

-------------------------------------------------------------------------------
-- Colourise a single die result if it hit the minimum (red) or maximum (green).
-- Dice with fewer than 10 sides aren't treated specially.
--
-- @returns coloured string
--
local function ColoredRoll( roll, min, max )
	if max == nil then
		max = min
		min = 1
	end
	if min == 1 and max < 10 then
		return roll
	end
	if roll == min then
		return "|cffff0000" .. roll .. "|r"
	end
	if roll == max then
		return "|cff00ff00" .. roll .. "|r"
	end
	return roll
end

-------------------------------------------------------------------------------
-- Duality dice colours. Each is an { r, g, b } triple of 0-1 floats kept in the
-- saved variables so players (colourblind members especially) can recolour them
-- from the options panel. The fallbacks here are used if the DB isn't ready yet
-- and match the original hard-coded green / orange / purple.
--
local DUALITY_FALLBACK = {
	dualityCritColor = { r = 0,    g = 1,    b = 0    },  -- matching dice (crit)
	dualityHopeColor = { r = 1,    g = 0.5,  b = 0    },  -- with Hope
	dualityFearColor = { r = 0.64, g = 0.21, b = 0.93 },  -- with Fear
}

-- Return the "rrggbb" hex string for a stored duality colour (keyed as above).
local function DualityHex( key )
	local c = ( Me.db and Me.db[key] ) or DUALITY_FALLBACK[key]
	return string.format( "%02x%02x%02x",
		floor( c.r * 255 + 0.5 ),
		floor( c.g * 255 + 0.5 ),
		floor( c.b * 255 + 0.5 ) )
end

-------------------------------------------------------------------------------
-- Build the human-readable roll line.
--
-- @param name   Roller's name.
-- @param you    true if the roller is the local player.
-- @param count  Number of dice.
-- @param sides  Sides per die.
-- @param mod    Signed modifier added to the sum.
-- @param rolls  Array of individual die results.
--
local function FormatRoll( name, you, count, sides, mod, rolls )
	local sum = 0
	for _, v in ipairs( rolls ) do
		sum = sum + v
	end

	-- Daggerheart "Duality dice": a single 2d12 is two contrasting dice -- the
	-- first is the Hope die, the second the Fear die. Matching faces are a crit
	-- (green); otherwise the higher die decides whether the roll is "with Hope"
	-- (orange) or "with Fear" (purple). Flat modifiers don't change which die
	-- won, so they leave the colour intact. The effect is deliberately narrow --
	-- exactly one 2d12 -- so it never fires on compound or other rolls.
	local duality   = count == 2 and sides == 12 and Me.db and Me.db.dualityEnabled
	local matchCrit = duality and rolls[1] == rolls[2]

	local rollstring
	if count == 1 then
		rollstring = ColoredRoll( sum + mod, 1 + mod, sides + mod )
		-- A natural min/max on a d10+ gets an exclamation flourish.
		if sides >= 10 and ( sum + mod == sides + mod or sum + mod == 1 + mod ) then
			rollstring = rollstring .. "!"
		end
	else
		-- Under Duality the total carries the only colour that matters, so show the
		-- two dice plainly -- the per-die min/max red/green just gets in the way.
		local function Die( i )
			if duality then
				return tostring( rolls[i] )
			end
			return tostring( ColoredRoll( rolls[i], sides ) )
		end

		rollstring = Die( 1 )
		for i = 2, count do
			if i == count then
				if count > 2 then
					rollstring = rollstring .. ", and " .. Die( i )
				else
					rollstring = rollstring .. " and " .. Die( i )
				end
			else
				rollstring = rollstring .. ", " .. Die( i )
			end
		end

		local total = sum + mod
		if matchCrit then
			total = "|cff" .. DualityHex( "dualityCritColor" ) .. total .. "|r"   -- critical (matching dice)
		elseif duality then
			if rolls[1] > rolls[2] then
				total = "|cff" .. DualityHex( "dualityHopeColor" ) .. total .. "|r"  -- with Hope
			else
				total = "|cff" .. DualityHex( "dualityFearColor" ) .. total .. "|r"  -- with Fear
			end
		end
		rollstring = rollstring .. " = " .. total
	end

	rollstring = rollstring .. " (" .. FormatDiceType( count, sides, mod ) .. ")"

	if you then
		return "You roll " .. rollstring
	end
	return name .. " rolls " .. rollstring
end

-------------------------------------------------------------------------------
-- Build the human-readable line for a compound roll -- one with more than one
-- kind of die (e.g. "2d6+1d6+7d12+25"). Same-sided terms have already been
-- merged into a single group by the parser, so 2d6+1d6 shows as one "3D6".
--
-- @param name    Roller's name.
-- @param you     true if the roller is the local player.
-- @param groups  Ordered list of { count, sides } die groups.
-- @param mod     Combined flat modifier.
-- @param rolls   Flat array of individual results, in group order.
--
local function FormatCompoundRoll( name, you, groups, mod, rolls )
	local sum = 0
	for _, v in ipairs( rolls ) do
		sum = sum + v
	end

	-- One "3, 5, 2 (3D6)" segment per die group, in the order they were rolled.
	local segments = {}
	local idx = 1
	for _, g in ipairs( groups ) do
		local dice = {}
		for i = 1, g.count do
			dice[i] = tostring( ColoredRoll( rolls[idx], g.sides ) )
			idx = idx + 1
		end
		local label = ( g.count == 1 and "D" or g.count .. "D" ) .. g.sides
		segments[#segments + 1] = table.concat( dice, ", " ) .. " (" .. label .. ")"
	end

	local body = table.concat( segments, " + " )
	if mod > 0 then
		body = body .. " + " .. mod
	elseif mod < 0 then
		body = body .. " - " .. ( -mod )
	end
	body = body .. " = " .. ( sum + mod )

	if you then
		return "You roll " .. body
	end
	return name .. " rolls " .. body
end

-------------------------------------------------------------------------------
-- Strip colour codes so the plain-text group broadcast is readable by everyone.
--
local function StripMessage( msg )
	msg = msg:gsub( "|c%x%x%x%x%x%x%x%x", "" )
	msg = msg:gsub( "|r", "" )
	return msg
end

-------------------------------------------------------------------------------
-- Print a fully matched dice roll, and (if it's ours) broadcast a plain-text
-- copy so non-addon group members can read it too.
--
local function PrintDiceRoll( name, count, sides, mod, rolls, broadcast )
	local isSelf = ( UnitName( "player" ) == name )

	if IsInGroup() or not isSelf then
		local message = FormatRoll( name, false, count, sides, mod, rolls )

		if broadcast and IsInGroup() and isSelf then
			local channel = IsInRaid() and "RAID" or "PARTY"
			local _, language = GetLanguageByIndex( 1 )
			SendChatMessage( "<Emberhollow> " .. StripMessage( message ), channel, language )
		end

		Me.PrintSystemMessage( message )
	else
		Me.PrintSystemMessage( FormatRoll( name, true, count, sides, mod, rolls ) )
	end
end

-------------------------------------------------------------------------------
-- Print a fully matched compound dice roll, broadcasting a plain-text copy for
-- non-addon group members just like PrintDiceRoll does.
--
local function PrintCompoundRoll( name, groups, mod, rolls, broadcast )
	local isSelf = ( UnitName( "player" ) == name )

	if IsInGroup() or not isSelf then
		local message = FormatCompoundRoll( name, false, groups, mod, rolls )

		if broadcast and IsInGroup() and isSelf then
			local channel = IsInRaid() and "RAID" or "PARTY"
			local _, language = GetLanguageByIndex( 1 )
			SendChatMessage( "<Emberhollow> " .. StripMessage( message ), channel, language )
		end

		Me.PrintSystemMessage( message )
	else
		Me.PrintSystemMessage( FormatCompoundRoll( name, true, groups, mod, rolls ) )
	end
end

-------------------------------------------------------------------------------
-- Print a vanilla (single, un-described) server roll.
--
local function PrintRoll( data )
	if data.handled then return end
	data.handled = true
	Me.PrintSystemMessage( string.format( RANDOM_ROLL_RESULT, data.name, data.roll, data.min, data.max ) )
end

-------------------------------------------------------------------------------
-- Drop entries from a roll queue once they're older than CLEAN_TIME.
--
local function CleanRollTable( t )
	if not t then return end
	local now = GetTime()
	while t[1] and now > t[1].time + CLEAN_TIME do
		table.remove( t, 1 )
	end
end

-------------------------------------------------------------------------------
-- Expand a roll descriptor into the ordered list of dice we expect the server
-- to return, as { min, max } pairs. Single-die-type and compound rolls flatten
-- to the same shape so CheckRolls can treat them uniformly.
--
local function ExpectedDice( r )
	local list = {}
	if r.compound then
		for _, g in ipairs( r.groups ) do
			for _ = 1, g.count do
				list[#list + 1] = { min = 1, max = g.sides }
			end
		end
	else
		for _ = 1, r.count do
			list[#list + 1] = { min = r.min, max = r.max }
		end
	end
	return list
end

-------------------------------------------------------------------------------
-- Try to pair pending roll descriptors with the raw server rolls we've seen.
--
local function CheckRolls( name )
	local rollInfo    = playerRollInfo[name]
	local serverRolls = playerServerRolls[name]

	CleanRollTable( rollInfo )
	CleanRollTable( serverRolls )

	if not rollInfo or not rollInfo[1] then return end
	if not serverRolls or not serverRolls[1] then return end

	while rollInfo[1] do
		local r      = rollInfo[1]
		local expect = ExpectedDice( r )
		local n      = #expect

		-- Wait until every die for this descriptor has come back.
		for i = 1, n do
			if not serverRolls[i] then
				return
			end
		end

		-- Verify the rolls we got are the ones we asked for. If a die's range
		-- doesn't line up, flush the mismatched prefix as raw rolls and bail; a
		-- later CheckRolls pass retries with whatever's left.
		local mismatch = false
		for i = 1, n do
			if serverRolls[i].min ~= expect[i].min or serverRolls[i].max ~= expect[i].max then
				for _ = 1, i do
					PrintRoll( serverRolls[1] )
					table.remove( serverRolls, 1 )
				end
				mismatch = true
				break
			end
		end
		if mismatch then break end

		if r.v then
			-- Vanilla single roll: just reprint the raw line.
			PrintRoll( serverRolls[1] )
			table.remove( serverRolls, 1 )
		else
			local rolls = {}
			for i = 1, n do
				rolls[i] = serverRolls[i].roll
				serverRolls[i].handled = true
			end
			for _ = 1, n do
				table.remove( serverRolls, 1 )
			end
			if r.compound then
				PrintCompoundRoll( name, r.groups, r.mod, rolls, true )
			else
				PrintDiceRoll( name, r.count, r.max, r.mod, rolls, true )
			end
		end

		table.remove( rollInfo, 1 )
	end
end

-------------------------------------------------------------------------------
-- Record an intended roll (ours or one announced over addon comms).
--
local function AddRollInfo( name, count, min, max, mod, vanilla )
	playerRollInfo[name] = playerRollInfo[name] or {}
	table.insert( playerRollInfo[name], {
		count = count or 1,
		min   = min or 1,
		max   = max or 100,
		mod   = mod or 0,
		v     = vanilla,
		time  = GetTime(),
	} )
	CheckRolls( name )
end

-------------------------------------------------------------------------------
-- Record an intended compound roll (ours or one announced over addon comms).
--
local function AddCompoundRollInfo( name, groups, mod )
	playerRollInfo[name] = playerRollInfo[name] or {}
	table.insert( playerRollInfo[name], {
		compound = true,
		groups   = groups,
		mod      = mod or 0,
		time     = GetTime(),
	} )
	CheckRolls( name )
end

-------------------------------------------------------------------------------
-- Record a raw server roll result.
--
local function AddServerRoll( name, roll, min, max )
	playerServerRolls[name] = playerServerRolls[name] or {}
	local data = {
		name = name, roll = roll, min = min, max = max,
		time = GetTime(), handled = false,
	}

	-- If nothing claims this roll within the grace period, print it raw.
	C_Timer.After( ROLL_TIMEOUT, function()
		PrintRoll( data )
	end )

	table.insert( playerServerRolls[name], data )
	CheckRolls( name )
end

-------------------------------------------------------------------------------
-- Announce an intended roll to the group and stash it locally.
--
local function SendRollMessage( count, min, max, mod, vanilla )
	-- count, min, max, mod, vanilla, rollType (rollType unused here)
	Me.SendComm( "R", count or 1, min or 1, max or 100, mod or 0, vanilla and true or false, "" )
	AddRollInfo( UnitName( "player" ), count, min, max, mod, vanilla )
end

-------------------------------------------------------------------------------
-- Announce a roll to the group, then drive RandomRoll() once per die. The
-- doingRoll guard stops our own RandomRoll hook from announcing these again.
--
local function DoRoll( count, sides, mod )
	SendRollMessage( count, 1, sides, mod or 0, nil )

	doingRoll = true
	for _ = 1, count do
		RandomRoll( 1, sides )
	end
	doingRoll = false
end

-------------------------------------------------------------------------------
-- (De)serialise a compound roll's die groups for the wire. "3:6,7:12" <-> a
-- list of { count, sides }. Order is preserved so the receiver expects the
-- server rolls in the same sequence we drove them.
--
local function SerializeGroups( groups )
	local parts = {}
	for i, g in ipairs( groups ) do
		parts[i] = g.count .. ":" .. g.sides
	end
	return table.concat( parts, "," )
end

local function DeserializeGroups( spec )
	local groups = {}
	for c, s in tostring( spec ):gmatch( "(%d+):(%d+)" ) do
		table.insert( groups, { count = tonumber( c ), sides = tonumber( s ) } )
	end
	return groups
end

-------------------------------------------------------------------------------
-- Announce an intended compound roll to the group, stash it locally, then drive
-- RandomRoll() once per die in group order. The doingRoll guard stops our own
-- RandomRoll hook from announcing these again.
--
local function DoCompoundRoll( groups, mod )
	Me.SendComm( "C", SerializeGroups( groups ), mod or 0 )
	AddCompoundRollInfo( UnitName( "player" ), groups, mod or 0 )

	doingRoll = true
	for _, g in ipairs( groups ) do
		for _ = 1, g.count do
			RandomRoll( 1, g.sides )
		end
	end
	doingRoll = false
end

-------------------------------------------------------------------------------
-- Parse a dice expression into die groups + a flat modifier.
--
-- Accepts any chain of XdY dice terms and bare numbers joined with + / -, e.g.
-- "2d6+1d6+7d12+6+7+3+9". Same-sided dice are merged (2d6+1d6 -> 3D6) and every
-- bare number folds into a single signed modifier. Dice can't be subtracted.
--
-- @returns groups (ordered {count,sides} list), mod, totalDice  -- or nil, errorKey
--
local function ParseDiceSpec( spec )
	spec = spec:gsub( "%s+", "" )
	if spec == "" then return nil, "empty" end

	local groups       = {}   -- ordered { count, sides }
	local indexBySides = {}   -- sides -> position in groups (for merging)
	local mod          = 0
	local totalDice    = 0

	local pos   = 1
	local first = true
	while pos <= #spec do
		local s, e, sign, count, sides = spec:find( "^([+-]?)(%d*)[dD](%d+)", pos )
		if s then
			-- A dice term.
			if sign == "-"                then return nil, "minusdice" end
			if not first and sign == "" then return nil, "syntax"    end

			count = ( count == "" ) and 1 or tonumber( count )
			sides = tonumber( sides )
			if count < 1     then return nil, "count0"   end
			if sides < 2     then return nil, "sides"    end
			if sides > 13476 then return nil, "sidesmax" end

			totalDice = totalDice + count
			local gi = indexBySides[sides]
			if gi then
				groups[gi].count = groups[gi].count + count
			else
				table.insert( groups, { count = count, sides = sides } )
				indexBySides[sides] = #groups
			end
			pos = e + 1
		else
			-- A bare numeric modifier.
			local s2, e2, sign2, num = spec:find( "^([+-]?)(%d+)", pos )
			if not s2                     then return nil, "syntax" end
			if not first and sign2 == "" then return nil, "syntax" end

			num = tonumber( num )
			if sign2 == "-" then num = -num end
			mod = mod + num
			pos = e2 + 1
		end
		first = false
	end

	if totalDice == 0 then return nil, "nodice" end
	return groups, mod, totalDice
end

-------------------------------------------------------------------------------
-- Public: perform a dice roll from a format string (e.g. "2d6+1", "d20", "4D4-2").
--
function Me.Roll( dice )
	local function UIError( msg )
		UIErrorsFrame:AddMessage( msg, 1.0, 0.0, 0.0 )
	end

	if type( dice ) ~= "string" then
		return UIError( "Invalid dice format." )
	end

	-- ATK / DEF shorthands: roll 2d12 plus the player's stored stat modifier so
	-- nobody has to remember (or type) their current bonus.
	if dice == "atk" or dice == "def" then
		return DoRoll( 2, 12, ( Me.db and Me.db[dice] ) or 0 )
	end

	local groups, mod, totalDice = ParseDiceSpec( dice )
	if not groups then
		local err = mod   -- on failure the 2nd return value is the error key
		if err == "minusdice" then
			return UIError( "Dice can't be subtracted -- use + to add another XdY." )
		elseif err == "count0" then
			return UIError( "You must have at least one die." )
		elseif err == "sides" then
			return UIError( "Must have at least two sides." )
		elseif err == "sidesmax" then
			return UIError( "Dice cannot have more than 13476 sides." )
		elseif err == "nodice" then
			return UIError( "You need at least one XdY dice term." )
		end
		return UIError( "Invalid dice format." )
	end

	if totalDice > 10 then
		return UIError( "You can only roll 10 dice at a time." )
	end

	if #groups == 1 then
		-- A single kind of die: keep the original path so its niceties (matching-
		-- dice crits, the natural min/max flourish) are preserved unchanged.
		DoRoll( groups[1].count, groups[1].sides, mod )
	else
		DoCompoundRoll( groups, mod )
	end
end

-------------------------------------------------------------------------------
-- Chat filters: hide the raw system roll lines (we reprint them ourselves) and
-- tidy up the <Emberhollow> group broadcasts.
--
local function RollSystemFilter( self, event, msg, ... )
	if msg:match( SYSTEM_ROLL_PATTERN ) then
		return true
	end
	return false
end

local function RollGroupFilter( self, event, msg, ... )
	if msg:match( "^<Emberhollow> %S+ rolls" ) then
		if Me.db.showGroupRolls then
			return false, "|cffffff00" .. msg:sub( 14 ) .. "|r", ...
		end
		return true
	end
	return false
end

-------------------------------------------------------------------------------
-- Incoming CHAT_MSG_SYSTEM: pick out roll results.
--
local function OnSystemMessage( message )
	local sender, roll, min, max = message:match( SYSTEM_ROLL_PATTERN )
	if sender then
		AddServerRoll( sender, tonumber( roll ), tonumber( min ), tonumber( max ) )
		return true
	end
end

-------------------------------------------------------------------------------
-- Post-hook on RandomRoll: catch native /roll usage so it gets the rich
-- treatment too (but not the rolls we ourselves drive in Me.Roll).
--
local function OnRandomRoll( min, max )
	min = tonumber( min )
	max = tonumber( max )
	if not min or not max then return end
	min = floor( min )
	max = floor( max )
	if min < 0 or max < 0 or min > 1000000 or max > 1000000 or max < min then
		return
	end

	if not doingRoll then
		SendRollMessage( 1, min, max, 0, true )
	end
end

-------------------------------------------------------------------------------
-- Addon-comm handler: another player announced a roll. (Called from Core.)
--
function Me.Dice_OnRollMessage( sender, count, min, max, mod, vanilla, _rollType )
	AddRollInfo( sender, count, min, max, mod, vanilla )
end

-------------------------------------------------------------------------------
-- Addon-comm handler: another player announced a compound roll. (Called from
-- Core.)
--
function Me.Dice_OnCompoundRollMessage( sender, spec, mod )
	AddCompoundRollInfo( sender, DeserializeGroups( spec ), mod or 0 )
end

-------------------------------------------------------------------------------
function Me.Dice_Init()
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_SYSTEM",       RollSystemFilter )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_PARTY",        RollGroupFilter )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_PARTY_LEADER", RollGroupFilter )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_RAID",         RollGroupFilter )
	ChatFrame_AddMessageEventFilter( "CHAT_MSG_RAID_LEADER",  RollGroupFilter )

	local f = CreateFrame( "Frame" )
	f:RegisterEvent( "CHAT_MSG_SYSTEM" )
	f:SetScript( "OnEvent", function( _, _, msg )
		OnSystemMessage( msg )
	end )

	hooksecurefunc( "RandomRoll", OnRandomRoll )
end
