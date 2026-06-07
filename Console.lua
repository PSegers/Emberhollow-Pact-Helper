-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Chat commands
-------------------------------------------------------------------------------
--
--   /dice [XdY+/-Z]    roll dice (also: /eph roll ...)
--   /eph               configuration & help
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

-------------------------------------------------------------------------------
-- /dice  -- roll dice
--
local function RollCommand( msg )
	msg = msg:gsub( "^%s+", "" ):gsub( "%s+$", "" )

	if msg == "" then
		Me.Print( "/dice (XdY[+/-]Z)" )
		Me.PrintSystemMessage( "- X is how many dice to roll." )
		Me.PrintSystemMessage( "- Y is how many sides those dice have." )
		Me.PrintSystemMessage( "- Z is added to / subtracted from the total." )
		Me.PrintSystemMessage( "- Chain terms with + / -, e.g. /dice 2d6+1d6+7d12+6 (max 10 dice)." )
		Me.PrintSystemMessage( "- /dice atk or /dice def rolls 2d12 + your stored ATK / DEF." )
		return
	end

	Me.Roll( msg:lower() )
end

-------------------------------------------------------------------------------
-- /eph  -- everything else
--
local function MainCommand( msg )
	local command, rest = msg:match( "^(%S*)%s*(.-)$" )
	command = command:lower()
	local rawRest = rest   -- original casing, for commands that take free text (marker names)
	rest = rest:lower()

	if command == "roll" or command == "dice" then
		RollCommand( rest )

	elseif command == "cheatsheet" or command == "cheat" or command == "cs" then
		Me.CheatSheet_Toggle()

	elseif command == "options" or command == "config" or command == "opt" then
		Me.Options_Open()

	elseif command == "marker" or command == "mark" then
		if Me.Marker_Command then Me.Marker_Command( rawRest ) end

	elseif command == "dm" then
		if rest == "on" or rest == "true" then
			Me.db.dmEnabled = true
		elseif rest == "off" or rest == "false" then
			Me.db.dmEnabled = false
		else
			Me.db.dmEnabled = not Me.db.dmEnabled
		end
		if Me.Marker_Refresh then Me.Marker_Refresh() end
		Me.Print( "DM mode " .. ( Me.db.dmEnabled and "|cff00ff00on|r -- you can edit marker names." or "|cffff0000off|r -- marker names are read-only." ) )

	elseif command == "minimap" then
		local show
		if rest == "on" then
			show = true
		elseif rest == "off" then
			show = false
		else
			show = Me.db.minimap and Me.db.minimap.hide   -- flip: hidden -> show
		end
		if Me.Minimap_SetShown then Me.Minimap_SetShown( show ) end
		Me.Print( "Minimap button " .. ( show and "|cff00ff00shown|r" or "|cffff0000hidden|r" ) .. "." )

	elseif command == "typing" then
		if rest == "on" then
			Me.db.typingEnabled = true
		elseif rest == "off" then
			Me.db.typingEnabled = false
		else
			Me.db.typingEnabled = not Me.db.typingEnabled
		end
		Me.Typing_RefreshButton()
		Me.Print( "Typing indicator " .. ( Me.db.typingEnabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r" ) .. "." )

	elseif command == "grouprolls" then
		if rest == "on" or rest == "true" then
			Me.db.showGroupRolls = true
		elseif rest == "off" or rest == "false" then
			Me.db.showGroupRolls = false
		else
			Me.db.showGroupRolls = not Me.db.showGroupRolls
		end
		Me.Print( "Show plain-text group rolls: " .. ( Me.db.showGroupRolls and "|cff00ff00on|r" or "|cffff0000off|r" ) .. "." )

	elseif command == "duality" then
		if rest == "on" or rest == "true" then
			Me.db.dualityEnabled = true
		elseif rest == "off" or rest == "false" then
			Me.db.dualityEnabled = false
		else
			Me.db.dualityEnabled = not Me.db.dualityEnabled
		end
		Me.Print( "2d12 Duality dice (crit / Hope / Fear): " .. ( Me.db.dualityEnabled and "|cff00ff00on|r" or "|cffff0000off|r" ) .. "." )

	elseif command == "atk" or command == "def" then
		if rest ~= "" then
			local n = tonumber( rest )
			if not n then
				Me.Print( "Usage: |cffffd100/eph " .. command .. " <number>|r (e.g. /eph " .. command .. " 5)." )
			else
				Me.db[command] = math.floor( n )
				Me.Print( command:upper() .. " modifier set to " .. Me.db[command] .. ". Roll it with |cffffd100/dice " .. command .. "|r." )
			end
		else
			Me.Print( command:upper() .. " modifier is " .. ( Me.db[command] or 0 ) .. ". Set with |cffffd100/eph " .. command .. " <n>|r, roll with |cffffd100/dice " .. command .. "|r." )
		end

	else
		Me.Print( "Emberhollow Pact Helper v" .. Me.version )
		Me.PrintSystemMessage( "- /dice (XdY[+/-]Z)  -- roll dice (chainable, e.g. 2d6+1d6+7d12+6)" )
		Me.PrintSystemMessage( "- /eph options  -- open the options panel (also: config, opt)" )
		Me.PrintSystemMessage( "- /eph cs  -- open the reference cheat sheet window (also: cheat, cheatsheet)" )
		Me.PrintSystemMessage( "- /eph marker  -- name the raid target icons (panel; syncs to your group). Also: /eph marker skull <name>, /eph marker list" )
		Me.PrintSystemMessage( "- /eph dm (on || off)  -- DM mode: only a DM can edit/clear the marker names" )
		Me.PrintSystemMessage( "- /eph minimap (on || off)  -- show/hide the minimap button (left: options, right: markers, shift-right: cheat sheet)" )
		Me.PrintSystemMessage( "- /eph typing (on || off)  -- toggle the typing indicator" )
		Me.PrintSystemMessage( "- Move the \"is typing...\" bar and toggle button in WoW's Edit Mode (drag them there)." )
		Me.PrintSystemMessage( "- /eph grouprolls (on || off)  -- show plain-text rolls from the group" )
		Me.PrintSystemMessage( "- /eph duality (on || off)  -- colour a single 2d12 by crit (green) / Hope (orange) / Fear (purple)" )
		Me.PrintSystemMessage( "- /eph atk (n) / /eph def (n)  -- set your ATK / DEF modifier" )
		Me.PrintSystemMessage( "- /dice atk / /dice def  -- roll 2d12 + your ATK / DEF" )
	end
end

-------------------------------------------------------------------------------
-- Register the slash commands at file-load time. Doing this here (rather than
-- inside an init function called later) guarantees the commands exist as long
-- as this file loads at all, independent of any other module.
--
-- /ephdice is a collision-proof alias; plain /dice is also registered but may
-- be claimed by another loaded addon (e.g. DiceMaster registers /dice too).
SLASH_EMBERHOLLOWDICE1 = "/dice"
SLASH_EMBERHOLLOWDICE2 = "/ephdice"
SlashCmdList["EMBERHOLLOWDICE"] = RollCommand

SLASH_EMBERHOLLOW1 = "/eph"
SLASH_EMBERHOLLOW2 = "/emberhollow"
SlashCmdList["EMBERHOLLOW"] = MainCommand

-- Kept for the bootstrap's call site; registration already happened above.
function Me.Console_Init()
end
