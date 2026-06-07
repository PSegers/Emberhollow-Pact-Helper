-------------------------------------------------------------------------------
-- Emberhollow Pact Helper
-------------------------------------------------------------------------------
--
-- Core module: shared namespace, saved variables, addon-comm plumbing and a
-- couple of small utility functions used by the other files.
--
-- The dice-rolling code and the typing indicator are fully self-contained with
-- no external libraries -- everything here uses the stock WoW API.
--

local ADDON_NAME, Me = ...

-- Make the namespace reachable from the global environment for debugging.
_G.EmberhollowPactHelper = Me

Me.version = C_AddOns.GetAddOnMetadata( ADDON_NAME, "Version" ) or "?"

-- Addon-message prefix. Only other EmberhollowPactHelper users answer to this,
-- so our traffic stays isolated from every other addon.
Me.PREFIX = "EPH1"

-- Field separator for our tiny wire format. A tab never appears in player
-- names, numbers or the channel headers we care about.
local SEP = "\t"

-------------------------------------------------------------------------------
-- Default saved variables.
--
local DB_DEFAULTS = {
	typingEnabled  = true,   -- broadcast/show the "is typing..." indicator
	showGroupRolls = false,  -- also show the plain-text <Emberhollow> roll line
	dualityEnabled   = true, -- Daggerheart "Duality dice": colour a single 2d12 total green (crit/matching), orange (Hope) or purple (Fear)
	atk = 0,                 -- ATK modifier rolled by "/dice atk" (2d12+ATK)
	def = 0,                 -- DEF modifier rolled by "/dice def" (2d12+DEF)

	-- Duality dice colours ({ r, g, b }, 0-1). Editable from the options panel so
	-- colourblind players can pick their own; defaults are green / orange / purple.
	dualityCritColor = { r = 0,    g = 1,    b = 0    },
	dualityHopeColor = { r = 1,    g = 0.5,  b = 0    },
	dualityFearColor = { r = 0.64, g = 0.21, b = 0.93 },

	-- Position stores for the typing bar and the manual toggle button, owned by
	-- EditModeExpanded-1.0. The library reads/writes x/y and per-Edit-Mode-layout
	-- profiles inside each; we just hand it persistent tables to live in. Both
	-- frames are now repositioned through WoW's Edit Mode (see Typing.lua).
	typingBarEditMode = {},
	typingButtonEditMode = {},

	-- Marker naming: custom RP names for the 8 raid target icons (Star..Skull),
	-- shared with the group over the "M" message. markerPanel remembers where the
	-- editor window was dragged (see Marker.lua).
	markerNames = { "", "", "", "", "", "", "", "" },
	markerPanel = {},

	-- "DM" mode: only a DM may edit/clear the marker names (others see them
	-- read-only and still receive updates). Toggled by /eph dm or the options.
	dmEnabled = false,

	-- Minimap launcher button settings table owned by LibDBIcon-1.0 (it stores
	-- hide + minimapPos here). See Minimap.lua.
	minimap = { hide = false },
}

-------------------------------------------------------------------------------
-- Print a "system" message in every chat frame registered for the SYSTEM
-- channel (mirrors the way Blizzard prints /roll results).
--
-- @param msg		Message to print.
-- @param channel	Optional chat channel that a frame must be registered for.
--					(nil => any frame that shows SYSTEM messages)
--
function Me.PrintSystemMessage( msg, channel )
	channel = channel or "SYSTEM"
	local info = ChatTypeInfo["SYSTEM"]

	for i = 1, NUM_CHAT_WINDOWS do
		local frame = _G["ChatFrame" .. i]
		if frame then
			for _, v in ipairs( { GetChatWindowMessages( i ) } ) do
				if v == channel then
					frame:AddMessage( msg, info.r, info.g, info.b )
					break
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- A short, prefixed line for help / status output. Always goes to the default
-- chat frame.
--
function Me.Print( msg )
	DEFAULT_CHAT_FRAME:AddMessage( "|cffffd100Emberhollow:|r " .. tostring( msg ) )
end

-------------------------------------------------------------------------------
-- Window styling: the shared look for our windows, modelled on Total RP's main
-- panels -- a parchment-textured interior under a soft dark "shadow" overlay,
-- inside the ornate gold dialog border, with white text on top. All stock WoW
-- textures; no bundled art.
--
-- Earlier attempts used a light parchment with dark "ink" text, but the paper
-- kept reading too dark for the text to stand out. Deliberately darkening the
-- interior and switching to white text (Me.TEXT_COLOR) gives high contrast that
-- reads cleanly, while the parchment grain keeps the RP feel.
--
-- The frame must inherit BackdropTemplate (for the gold edge); we paint the
-- interior ourselves (a background texture + a translucent black overlay) so the
-- brightness is fully under our control rather than at the mercy of a backdrop
-- bgFile.
--
local FRAME_BORDER = {
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	edgeSize = 32,
}

-- Warm near-white for text drawn on the shadowed parchment.
Me.TEXT_COLOR = { r = 0.98, g = 0.95, b = 0.88 }

local function StyleInterior( frame )
	if frame.ephStyled then return end   -- build the textures once
	frame.ephStyled = true

	-- Parchment grain, inset to sit inside the gold border.
	local bg = frame:CreateTexture( nil, "BACKGROUND" )
	bg:SetPoint( "TOPLEFT", 11, -12 )
	bg:SetPoint( "BOTTOMRIGHT", -12, 11 )
	bg:SetTexture( "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal" )

	-- Warm dark overlay that deepens the paper into a rich brown so white text
	-- lifts cleanly off it (tinted, not flat grey).
	local shade = frame:CreateTexture( nil, "BORDER" )
	shade:SetAllPoints( bg )
	shade:SetColorTexture( 0.06, 0.03, 0.01, 0.72 )
end

function Me.StyleParchmentFrame( frame )
	if not frame or not frame.SetBackdrop then return end
	frame:SetBackdrop( FRAME_BORDER )
	frame:SetBackdropBorderColor( 1, 1, 1 )  -- natural gold border
	StyleInterior( frame )
end

-------------------------------------------------------------------------------
-- Shared click handler for the launchers (the minimap button and the Total RP
-- toolbar button both route here):
--   left-click          -> Options
--   right-click         -> Marker names
--   shift + right-click -> Cheat sheet
--
function Me.LauncherClick( mouseButton )
	if mouseButton == "RightButton" then
		if IsShiftKeyDown() then
			Me.CheatSheet_Toggle()
		else
			Me.Marker_Toggle()
		end
	else
		Me.Options_Open()
	end
end

-------------------------------------------------------------------------------
-- Which group channel should an addon message go out on?
--
-- @returns "RAID", "PARTY", or nil when we're not in a (home) group.
--
function Me.GroupChannel()
	-- Roleplay feature: ignore instance/LFG groups entirely.
	if IsInGroup( LE_PARTY_CATEGORY_INSTANCE ) and not IsInGroup( LE_PARTY_CATEGORY_HOME ) then
		return nil
	end
	if IsInRaid( LE_PARTY_CATEGORY_HOME ) then
		return "RAID"
	elseif IsInGroup( LE_PARTY_CATEGORY_HOME ) then
		return "PARTY"
	end
	return nil
end

-------------------------------------------------------------------------------
-- Send an addon message to our group, if we're in one.
--
-- @param ...	Pieces of the message; numbers/booleans are stringified and
--				joined with the field separator.
--
function Me.SendComm( ... )
	local channel = Me.GroupChannel()
	if not channel then return end

	local n = select( "#", ... )
	local parts = {}
	for i = 1, n do
		local v = select( i, ... )
		if type( v ) == "boolean" then
			v = v and "1" or "0"
		elseif v == nil then
			v = ""
		end
		parts[i] = tostring( v )
	end

	C_ChatInfo.SendAddonMessage( Me.PREFIX, table.concat( parts, SEP ), channel )
end

-------------------------------------------------------------------------------
-- Route an incoming addon message to the right handler.
--
local function OnAddonMessage( prefix, text, _channel, sender )
	if prefix ~= Me.PREFIX then return end

	-- Best-effort cross-realm support: drop the realm tag.
	if sender:find( "-" ) then
		sender = sender:match( "(.+)%-" )
	end

	-- Never react to our own broadcasts.
	if sender == UnitName( "player" ) then return end

	local fields = { strsplit( SEP, text ) }
	local msgtype = table.remove( fields, 1 )

	if msgtype == "R" then
		-- count, min, max, mod, vanilla, rollType
		Me.Dice_OnRollMessage(
			sender,
			tonumber( fields[1] ),
			tonumber( fields[2] ),
			tonumber( fields[3] ),
			tonumber( fields[4] ),
			fields[5] == "1",
			fields[6] ~= "" and fields[6] or nil
		)
	elseif msgtype == "C" then
		-- compound roll: spec ("count:sides,..."), mod
		Me.Dice_OnCompoundRollMessage( sender, fields[1], tonumber( fields[2] ) )
	elseif msgtype == "T" then
		-- typing
		Me.Typing_OnTyping( sender, fields[1] == "1" )
	elseif msgtype == "M" then
		-- marker name: index (1-8), name (may be empty to clear)
		if Me.Marker_OnMessage then
			Me.Marker_OnMessage( sender, tonumber( fields[1] ), fields[2] or "" )
		end
	end
end

-------------------------------------------------------------------------------
-- Bootstrap.
--
local bootstrap = CreateFrame( "Frame" )
bootstrap:RegisterEvent( "ADDON_LOADED" )
bootstrap:RegisterEvent( "PLAYER_LOGIN" )
bootstrap:SetScript( "OnEvent", function( self, event, arg1 )
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		-- Initialise saved variables with our defaults.
		EmberhollowPactHelperDB = EmberhollowPactHelperDB or {}

		-- Migrate the old matchcrit setting into the renamed "duality" toggle.
		if EmberhollowPactHelperDB.matchCritEnabled ~= nil and EmberhollowPactHelperDB.dualityEnabled == nil then
			EmberhollowPactHelperDB.dualityEnabled = EmberhollowPactHelperDB.matchCritEnabled
		end
		EmberhollowPactHelperDB.matchCritEnabled = nil

		for k, v in pairs( DB_DEFAULTS ) do
			if EmberhollowPactHelperDB[k] == nil then
				if type( v ) == "table" then
					-- Copy table defaults (e.g. colours) so edits don't mutate DB_DEFAULTS.
					local copy = {}
					for kk, vv in pairs( v ) do copy[kk] = vv end
					EmberhollowPactHelperDB[k] = copy
				else
					EmberhollowPactHelperDB[k] = v
				end
			end
		end
		Me.db = EmberhollowPactHelperDB

	elseif event == "PLAYER_LOGIN" then
		C_ChatInfo.RegisterAddonMessagePrefix( Me.PREFIX )

		local comm = CreateFrame( "Frame" )
		comm:RegisterEvent( "CHAT_MSG_ADDON" )
		comm:SetScript( "OnEvent", function( _, _, ... )
			OnAddonMessage( ... )
		end )

		-- Hand control to the feature modules. Each runs in its own pcall so a
		-- failure in one never stops the others from initialising (in
		-- particular, the slash commands must always register).
		local function SafeInit( name, fn )
			if type( fn ) ~= "function" then
				Me.Print( "|cffff0000" .. name .. " module failed to load (its file errored).|r" )
				return
			end
			local ok, err = pcall( fn )
			if not ok then
				Me.Print( "|cffff0000error initialising " .. name .. ":|r " .. tostring( err ) )
			end
		end

		SafeInit( "Dice", Me.Dice_Init )
		SafeInit( "Typing", Me.Typing_Init )
		SafeInit( "CheatSheet", Me.CheatSheet_Init )
		SafeInit( "Marker", Me.Marker_Init )
		SafeInit( "Minimap", Me.Minimap_Init )
		SafeInit( "Options", Me.Options_Init )
			SafeInit( "Console", Me.Console_Init )

		Me.Print( "v" .. Me.version .. " loaded. Type |cffffd100/eph|r for help, |cffffd100/dice|r to roll." )
	end
end )
