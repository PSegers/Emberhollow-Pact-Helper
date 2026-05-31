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

	-- Daggerheart-style "matching dice" crit: a 2d12 whose two dice show the
	-- same face. Kept deliberately narrow (exactly 2 dice, 12 sides) rather than
	-- "any doubles" so ordinary matched small dice don't read as crits. The total
	-- is coloured with the same green ColoredRoll uses for a max die.
	local matchCrit = Me.db and Me.db.matchCritEnabled and count == 2 and sides == 12 and rolls[1] == rolls[2]

	local rollstring
	if count == 1 then
		rollstring = ColoredRoll( sum + mod, 1 + mod, sides + mod )
		-- A natural min/max on a d10+ gets an exclamation flourish.
		if sides >= 10 and ( sum + mod == sides + mod or sum + mod == 1 + mod ) then
			rollstring = rollstring .. "!"
		end
	else
		rollstring = tostring( ColoredRoll( rolls[1], sides ) )
		for i = 2, count do
			if i == count then
				if count > 2 then
					rollstring = rollstring .. ", and " .. ColoredRoll( rolls[i], sides )
				else
					rollstring = rollstring .. " and " .. ColoredRoll( rolls[i], sides )
				end
			else
				rollstring = rollstring .. ", " .. ColoredRoll( rolls[i], sides )
			end
		end

		local total = sum + mod
		if matchCrit then
			total = "|cff00ff00" .. total .. "|r"
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
		local r = rollInfo[1]
		local rolls = {}

		for i = 1, r.count do
			if not serverRolls[i] then
				return -- need to wait for more rolls
			end

			table.insert( rolls, serverRolls[i].roll )

			if serverRolls[i].min ~= r.min or serverRolls[i].max ~= r.max then
				-- These rolls don't match what we expected; flush them as raw.
				for _ = 1, i do
					PrintRoll( serverRolls[1] )
					table.remove( serverRolls, 1 )
				end
				rolls = nil
				break
			end
		end

		if rolls then
			if r.v then
				-- Vanilla single roll.
				PrintRoll( serverRolls[1] )
				table.remove( serverRolls, 1 )
				table.remove( rollInfo, 1 )
			else
				for _ = 1, r.count do
					serverRolls[1].handled = true
					table.remove( serverRolls, 1 )
				end
				table.remove( rollInfo, 1 )
				PrintDiceRoll( name, r.count, r.max, r.mod, rolls, true )
			end
		end
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

	local count, sides, modtype, mod = dice:match( "^%s*(%d*)[dD](%d+)([+-]?)(%d*)%s*$" )
	if not count then
		return UIError( "Invalid dice format." )
	end

	count   = count   == "" and 1  or tonumber( count )
	sides   = sides   == "" and 20 or tonumber( sides )
	modtype = modtype == "" and "+" or modtype
	mod     = mod     == "" and 0  or tonumber( mod )

	if count == 0    then return UIError( "You must have at least one die." )       end
	if count > 10    then return UIError( "You can only roll 10 dice at a time." )  end
	if sides < 2     then return UIError( "Must have at least two sides." )         end
	if sides > 13476 then return UIError( "Dice cannot have more than 13476 sides." ) end

	if modtype == "-" then
		mod = -mod
	end

	DoRoll( count, sides, mod )
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
