-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Marker naming
-------------------------------------------------------------------------------
--
-- Give the eight raid target icons (Star, Circle, ... Skull) custom roleplay
-- names -- e.g. Skull = "The Cursed Altar" -- so a group can agree on what each
-- marker stands for. Names are shared with other EmberhollowPactHelper users in
-- your (home) party/raid over the "M" wire message and stored in saved
-- variables; the panel built here is the one place to view and edit them.
--
-- Open / close the panel with  /eph marker  (Me.Marker_Toggle). Names can also
-- be set straight from chat with  /eph marker <icon> <name>.
--
-- Editing is gated behind "DM" mode (Me.db.dmEnabled, toggled with /eph dm or
-- the options panel). A DM can edit the names and use the panel's "Clear All"
-- button (which asks for confirmation first); everyone else sees the names as
-- read-only and still receives the DM's updates over the wire.
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

-- Are we acting as the group's DM (the only role allowed to edit names)?
local function IsDM()
	return Me.db and Me.db.dmEnabled and true or false
end

-------------------------------------------------------------------------------
-- The eight markers. We prefer WoW's own localized names (RAID_TARGET_1..8) and
-- fall back to plain English if a client somehow lacks them.
--
local FALLBACK_NAME = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local MARKER_NAME   = {}
for i = 1, 8 do
	MARKER_NAME[i] = _G["RAID_TARGET_" .. i] or FALLBACK_NAME[i]
end

-- Slash-command aliases for the icons, so "/eph marker skull ..." works as well
-- as "/eph marker 8 ...".
local NAME_TO_INDEX = {
	star = 1, circle = 2, diamond = 3, triangle = 4,
	moon = 5, square = 6, cross = 7, x = 7, skull = 8,
}

-- An inline raid-target icon for chat output.
local function IconText( i )
	return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":0|t"
end

local frame        -- the panel (EmberhollowMarkerFrame)
local rows         -- per-marker { icon, label, edit } widgets, [1..8]
local clearButton  -- the DM-only "Clear All" button

-- Geometry. The eight rows sit at the top; the window is resizable (the edit
-- boxes stretch with the width) and remembers its size/position.
local ROW_H          = 28
local TOP            = 38   -- y-offset of the first row from the top
local DEFAULT_WIDTH  = 300
local DEFAULT_HEIGHT = TOP + ROW_H * 8 + 44   -- rows + room for the Clear button
local MIN_WIDTH      = 260
local MIN_HEIGHT     = DEFAULT_HEIGHT          -- the 8-row list needs its full height

-------------------------------------------------------------------------------
-- Persist / restore where the player dragged the panel and how big they made
-- it. Lives in Me.db.markerPanel, seeded by Core's DB_DEFAULTS.
--
local function SavePlacement()
	if not frame then return end
	local cfg = Me.db.markerPanel
	local point, _, relPoint, x, y = frame:GetPoint( 1 )
	cfg.point    = point
	cfg.relPoint = relPoint
	cfg.x        = x
	cfg.y        = y
	cfg.width    = frame:GetWidth()
	cfg.height   = frame:GetHeight()
end

local function RestorePlacement()
	if not frame then return end
	local cfg = Me.db.markerPanel

	frame:SetSize( cfg.width or DEFAULT_WIDTH, cfg.height or DEFAULT_HEIGHT )

	frame:ClearAllPoints()
	if cfg.point then
		frame:SetPoint( cfg.point, UIParent, cfg.relPoint or cfg.point, cfg.x or 0, cfg.y or 0 )
	else
		frame:SetPoint( "CENTER" )
	end
end

-------------------------------------------------------------------------------
-- Read a row's edit box, store the (trimmed) name and broadcast the change.
-- No-ops if the text hasn't actually changed, so simply tabbing through the
-- boxes doesn't spam the group.
--
local function CommitRow( i, edit )
	edit:ClearFocus()
	if not IsDM() then return end   -- only the DM may change names

	local text = ( edit:GetText() or "" ):gsub( "^%s+", "" ):gsub( "%s+$", "" )

	if ( Me.db.markerNames[i] or "" ) == text then return end

	Me.db.markerNames[i] = text
	Me.SendComm( "M", i, text )
end

-------------------------------------------------------------------------------
-- Clear every marker name (DM only), broadcasting each clear so the group's
-- panels empty out too. Invoked after the confirmation popup is accepted.
--
local function ClearAllNames()
	if not IsDM() then return end
	for i = 1, 8 do
		Me.db.markerNames[i] = ""
		Me.SendComm( "M", i, "" )
	end
	if Me.Marker_Refresh then Me.Marker_Refresh() end
	Me.Print( "Cleared all marker names." )
end

-- Confirmation dialog shown before the Clear All button wipes the names.
StaticPopupDialogs["EPH_MARKER_CLEAR"] = {
	text         = "Clear all marker names for you and your group?",
	button1      = YES,
	button2      = NO,
	OnAccept     = ClearAllNames,
	timeout      = 0,
	whileDead    = true,
	hideOnEscape = true,
	preferredIndex = 3,   -- avoids tainting Blizzard's UIParent popups
}

-------------------------------------------------------------------------------
-- Print the currently-named markers to chat (/eph marker list).
--
local function PrintList()
	local any = false
	for i = 1, 8 do
		local nm = Me.db.markerNames[i]
		if nm and nm ~= "" then
			if not any then
				Me.Print( "Marker names:" )
				any = true
			end
			Me.PrintSystemMessage( IconText( i ) .. " " .. MARKER_NAME[i] .. "  -  |cffffffff" .. nm .. "|r" )
		end
	end
	if not any then
		Me.Print( "No markers named yet. Try |cffffd100/eph marker skull The Cursed Altar|r." )
	end
end

-------------------------------------------------------------------------------
-- Sync each edit box's text from saved variables and apply the current DM mode:
-- DMs get editable boxes and the Clear All button; everyone else sees the names
-- read-only with no Clear button. Skips any box the player is actively typing in
-- so an incoming group update can't yank text out from under them.
--
function Me.Marker_Refresh()
	if not frame or not rows then return end

	local dm = IsDM()
	for i = 1, 8 do
		local edit = rows[i].edit
		if not edit:HasFocus() then
			edit:SetText( Me.db.markerNames[i] or "" )
			edit:SetCursorPosition( 0 )
		end
		edit:SetEnabled( dm )   -- non-DMs can read but not edit
	end

	if clearButton then
		clearButton:SetShown( dm )
	end
end

-------------------------------------------------------------------------------
-- Show / hide the panel. Called from "/eph marker".
--
function Me.Marker_Toggle()
	if not frame then return end   -- init failed

	if frame:IsShown() then
		frame:Hide()
	else
		Me.Marker_Refresh()
		frame:Show()
	end
end

-------------------------------------------------------------------------------
-- "/eph marker ..." subcommand. Forms:
--   (empty)            -> open / close the panel
--   list               -> print the named markers to chat
--   <icon> <name>      -> set a marker's name (icon = 1-8 or star/skull/...)
--   <icon>             -> clear that marker's name
--
-- `rest` arrives with its original casing (Console hands us the raw text) so
-- names keep their capitalisation.
--
function Me.Marker_Command( rest )
	rest = ( rest or "" ):gsub( "^%s+", "" ):gsub( "%s+$", "" )

	if rest == "" then
		Me.Marker_Toggle()
		return
	end

	local arg, name = rest:match( "^(%S+)%s*(.-)$" )
	local key = arg:lower()

	if key == "list" then
		PrintList()
		return
	end

	local idx = NAME_TO_INDEX[key] or tonumber( arg )
	if not idx or idx < 1 or idx > 8 or idx ~= math.floor( idx ) then
		Me.Print( "Usage: |cffffd100/eph marker <icon> <name>|r -- icon is 1-8 or star/circle/diamond/triangle/moon/square/cross/skull." )
		Me.PrintSystemMessage( "- |cffffd100/eph marker|r alone opens the panel; |cffffd100/eph marker list|r prints the current names." )
		return
	end

	-- Setting / clearing a name is a DM-only action.
	if not IsDM() then
		Me.Print( "Only a DM can edit marker names. Enable DM mode with |cffffd100/eph dm on|r." )
		return
	end

	name = name:gsub( "^%s+", "" ):gsub( "%s+$", "" )
	Me.db.markerNames[idx] = name
	Me.SendComm( "M", idx, name )
	Me.Marker_Refresh()

	if name == "" then
		Me.Print( "Cleared the name for " .. IconText( idx ) .. " " .. MARKER_NAME[idx] .. "." )
	else
		Me.Print( "Set " .. IconText( idx ) .. " " .. MARKER_NAME[idx] .. " = |cffffffff" .. name .. "|r." )
	end
end

-------------------------------------------------------------------------------
-- Incoming "M" message from a groupmate: store and (if visible) refresh.
-- Own-broadcast suppression is handled upstream in Core's OnAddonMessage.
--
function Me.Marker_OnMessage( sender, index, name )
	if not Me.db then return end
	if not index or index < 1 or index > 8 then return end

	Me.db.markerNames[index] = name or ""
	if frame and frame:IsShown() then
		Me.Marker_Refresh()
	end
end

-------------------------------------------------------------------------------
-- Build the panel and wire it up. Registered with Core's SafeInit.
--
function Me.Marker_Init()
	-- Defensive: Core seeds these, but never assume.
	Me.db.markerNames = Me.db.markerNames or {}
	Me.db.markerPanel = Me.db.markerPanel or {}
	if Me.db.dmEnabled == nil then Me.db.dmEnabled = false end

	local f = CreateFrame( "Frame", "EmberhollowMarkerFrame", UIParent, "BackdropTemplate" )
	f:SetSize( DEFAULT_WIDTH, DEFAULT_HEIGHT )
	f:SetPoint( "CENTER" )
	f:SetFrameStrata( "HIGH" )
	f:SetToplevel( true )
	f:EnableMouse( true )
	f:SetMovable( true )
	f:SetResizable( true )
	f:SetClampedToScreen( true )
	if f.SetResizeBounds then
		f:SetResizeBounds( MIN_WIDTH, MIN_HEIGHT )
	elseif f.SetMinResize then
		f:SetMinResize( MIN_WIDTH, MIN_HEIGHT )
	end
	f:Hide()

	-- Shadowed-parchment look + gold border, shared with the cheat-sheet window.
	Me.StyleParchmentFrame( f )
	local tc = Me.TEXT_COLOR

	local title = f:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	title:SetPoint( "TOP", 0, -14 )
	title:SetText( "Marker Names" )
	title:SetTextColor( tc.r, tc.g, tc.b )

	local close = CreateFrame( "Button", nil, f, "UIPanelCloseButton" )
	close:SetPoint( "TOPRIGHT", -3, -3 )

	-- DM-only "Clear All" button (asks for confirmation first). Visibility is
	-- driven by Me.Marker_Refresh based on DM mode.
	clearButton = CreateFrame( "Button", nil, f, "UIPanelButtonTemplate" )
	clearButton:SetSize( 96, 22 )
	clearButton:SetPoint( "BOTTOM", 0, 12 )
	clearButton:SetText( "Clear All" )
	clearButton:SetScript( "OnClick", function() StaticPopup_Show( "EPH_MARKER_CLEAR" ) end )
	clearButton:Hide()

	-- The eight rows: icon + localized name + an edit box for the RP name.
	rows = {}
	for i = 1, 8 do
		local row = CreateFrame( "Frame", nil, f )
		row:SetHeight( ROW_H )
		row:SetPoint( "TOPLEFT",  f, "TOPLEFT",  18, -TOP - ( i - 1 ) * ROW_H )
		row:SetPoint( "TOPRIGHT", f, "TOPRIGHT", -18, -TOP - ( i - 1 ) * ROW_H )

		local icon = row:CreateTexture( nil, "ARTWORK" )
		icon:SetSize( 20, 20 )
		icon:SetPoint( "LEFT", 0, 0 )
		icon:SetTexture( "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i )

		local label = row:CreateFontString( nil, "ARTWORK", "GameFontHighlightSmall" )
		label:SetPoint( "LEFT", icon, "RIGHT", 6, 0 )
		label:SetWidth( 54 )
		label:SetJustifyH( "LEFT" )
		label:SetText( MARKER_NAME[i] )
		label:SetTextColor( tc.r, tc.g, tc.b )

		local edit = CreateFrame( "EditBox", nil, row, "InputBoxTemplate" )
		edit:SetHeight( 20 )
		edit:SetPoint( "LEFT", label, "RIGHT", 8, 0 )
		edit:SetPoint( "RIGHT", row, "RIGHT", -6, 0 )   -- stretch with the window
		edit:SetAutoFocus( false )
		edit:SetMaxLetters( 50 )
		edit:SetScript( "OnEnterPressed",   function( self ) CommitRow( i, self ) end )
		edit:SetScript( "OnEditFocusLost",  function( self ) CommitRow( i, self ) end )
		edit:SetScript( "OnEscapePressed",  function( self ) self:ClearFocus() end )

		rows[i] = { icon = icon, label = label, edit = edit }
	end

	-- Drag anywhere on the frame to move it; remember where it lands.
	f:RegisterForDrag( "LeftButton" )
	f:SetScript( "OnDragStart", f.StartMoving )
	f:SetScript( "OnDragStop", function( self )
		self:StopMovingOrSizing()
		SavePlacement()
	end )

	-- Resize grip in the bottom-right corner (matches the cheat-sheet window).
	local resize = CreateFrame( "Button", nil, f )
	resize:SetSize( 16, 16 )
	resize:SetPoint( "BOTTOMRIGHT", -5, 5 )
	resize:SetNormalTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" )
	resize:SetPushedTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down" )
	resize:SetHighlightTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight" )
	resize:SetScript( "OnMouseDown", function() f:StartSizing( "BOTTOMRIGHT" ) end )
	resize:SetScript( "OnMouseUp", function()
		f:StopMovingOrSizing()
		SavePlacement()
	end )

	-- Sync boxes on show; capture placement on close (the X button).
	f:SetScript( "OnShow", Me.Marker_Refresh )
	f:HookScript( "OnHide", SavePlacement )

	frame = f
	RestorePlacement()
end
