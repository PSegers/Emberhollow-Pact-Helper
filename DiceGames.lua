-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Dice Games hub
-------------------------------------------------------------------------------
--
-- A small framework for self-contained dice games (Farkle is the first; more
-- are planned). This file owns three things every game shares:
--
--   1. A custom dice RNG (Me.RollDie) that does NOT use WoW's /roll. The stock
--      RandomRoll can only roll a plain N-sided die, so it can't express the
--      weighted "special dice" these games will use. A die here is just a list
--      of six face weights; the regular die is fair ({1,1,1,1,1,1}) and future
--      special dice simply hand over different weights.
--   2. A game registry (Me.DiceGames_Register) so a new game is one new file
--      that registers itself -- no edits here.
--   3. A shared parchment window builder (Me.DiceGames_CreateWindow) matching
--      the cheat-sheet / marker windows (Me.StyleParchmentFrame + gold border,
--      white text, drag-to-move, Escape-to-close, remembered position).
--
-- Open the hub with  /eph dicegames  (Me.DiceGames_Toggle).
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

-------------------------------------------------------------------------------
-- Custom dice RNG.
--
-- A die definition is { name = ..., weights = { w1..w6 } }, one weight per face
-- 1-6. Equal weights = a fair die. We never touch RandomRoll, so these games
-- are fully independent of the /dice feature and never hit the EPH1 wire.
--
Me.REGULAR_DIE = { id = "regular", name = "Regular die", weights = { 1, 1, 1, 1, 1, 1 } }

function Me.RollDie( die )
	die = die or Me.REGULAR_DIE
	local w = die.weights or Me.REGULAR_DIE.weights

	local total = 0
	for face = 1, 6 do
		total = total + ( w[face] or 0 )
	end
	if total <= 0 then return math.random( 1, 6 ) end   -- degenerate; fall back to fair

	local r   = math.random() * total
	local acc = 0
	for face = 1, 6 do
		acc = acc + ( w[face] or 0 )
		if r < acc then return face end
	end
	return 6   -- floating-point safety net
end

-------------------------------------------------------------------------------
-- Dice ownership + the Farkle dice "pool".
--
-- Ownership is a count per die id, 0..OWN_MAX (the regular die is unlimited).
-- The pool is six die ids that the games roll with; duplicates are allowed, but
-- you can't put more copies of a die in the pool than you own. Both live in
-- Me.db (seeded by Core).
--
local OWN_MAX = 6   -- you can own up to six of each die

function Me.DiceGames_GetDie( id )
	if not id or id == "regular" then return Me.REGULAR_DIE end
	return ( Me.DICE_BY_ID and Me.DICE_BY_ID[id] ) or Me.REGULAR_DIE
end

-- How many of a die the player owns (0..OWN_MAX). The regular die is unlimited.
function Me.DiceGames_GetOwnedCount( id )
	if id == "regular" then return OWN_MAX end
	local v = Me.db and Me.db.diceOwned and Me.db.diceOwned[id]
	if type( v ) == "boolean" then return v and OWN_MAX or 0 end   -- migrate the old boolean form
	return v or 0
end

function Me.DiceGames_IsOwned( id )
	return Me.DiceGames_GetOwnedCount( id ) > 0
end

-- How many pool slots currently hold this die (optionally ignoring one slot).
function Me.DiceGames_PoolCount( id, exceptSlot )
	local pool = ( Me.db and Me.db.dicePool ) or {}
	local n = 0
	for i = 1, 6 do
		if i ~= exceptSlot and pool[i] == id then n = n + 1 end
	end
	return n
end

-- Set how many of a die you own (clamped 0..OWN_MAX). Trims any pool slots that
-- now exceed what you own back to the regular die.
function Me.DiceGames_SetOwnedCount( id, n )
	if id == "regular" then return end
	n = math.max( 0, math.min( OWN_MAX, math.floor( n or 0 ) ) )
	Me.db.diceOwned = Me.db.diceOwned or {}
	Me.db.diceOwned[id] = ( n > 0 ) and n or nil

	local pool = Me.db.dicePool or {}
	local seen = 0
	for i = 1, 6 do
		if pool[i] == id then
			seen = seen + 1
			if seen > n then pool[i] = "regular" end
		end
	end
end

-- Put a die in a pool slot, unless that would use more copies than you own.
-- Returns true on success, false if it was capped.
function Me.DiceGames_SetPoolSlot( i, id )
	if i < 1 or i > 6 then return false end
	Me.db.dicePool = Me.db.dicePool or {}
	if id ~= "regular" and Me.DiceGames_PoolCount( id, i ) >= Me.DiceGames_GetOwnedCount( id ) then
		return false
	end
	Me.db.dicePool[i] = id
	return true
end

-- The six die definitions currently in the pool (used by Farkle). Any slot
-- holding an unowned / unknown die falls back to the regular die.
function Me.DiceGames_GetPool()
	local saved = Me.db and Me.db.dicePool
	local pool = {}
	for i = 1, 6 do
		local id = ( saved and saved[i] ) or "regular"
		if not Me.DiceGames_IsOwned( id ) then id = "regular" end
		pool[i] = Me.DiceGames_GetDie( id )
	end
	return pool
end

-------------------------------------------------------------------------------
-- Game registry. Each game registers a descriptor at file load:
--   { id = "farkle", name = "Farkle", blurb = "...", onPlay = function() end }
-- onPlay is called when the player picks the game from the hub.
--
Me.DiceGames = Me.DiceGames or {}

function Me.DiceGames_Register( def )
	if not def or not def.id then return end
	table.insert( Me.DiceGames, def )
	if Me.DiceGames_RefreshHub then Me.DiceGames_RefreshHub() end
end

-------------------------------------------------------------------------------
-- Shared parchment window builder. Returns a hidden, movable, closable frame
-- styled like the rest of the addon's windows. `cfg` is a saved-vars table the
-- window remembers its position in; `globalName` is needed for Escape-to-close.
--
-- The returned frame carries:
--   .TitleText        -- centred title FontString (set its text per window)
--   .RestorePlacement -- call after building to position it
--
function Me.DiceGames_CreateWindow( globalName, cfg, width, height )
	local f = CreateFrame( "Frame", globalName, UIParent, "BackdropTemplate" )
	f:SetSize( width, height )
	f:SetFrameStrata( "HIGH" )
	f:SetToplevel( true )
	f:EnableMouse( true )
	f:SetMovable( true )
	f:SetClampedToScreen( true )
	-- Resizable from the bottom-right grip, like the cheat-sheet / marker
	-- windows. The starting size doubles as the minimum so the layout always
	-- fits; the player can only grow the window from there.
	f:SetResizable( true )
	if f.SetResizeBounds then
		f:SetResizeBounds( width, height )
	elseif f.SetMinResize then
		f:SetMinResize( width, height )
	end
	f:Hide()

	-- Shadowed-parchment look + gold border, shared with the other windows.
	Me.StyleParchmentFrame( f )
	local tc = Me.TEXT_COLOR

	local title = f:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	title:SetPoint( "TOP", 0, -14 )
	title:SetTextColor( tc.r, tc.g, tc.b )
	f.TitleText = title

	local close = CreateFrame( "Button", nil, f, "UIPanelCloseButton" )
	close:SetPoint( "TOPRIGHT", -3, -3 )

	-- Remember where the player drags it and how big they make it.
	local function Save()
		local point, _, relPoint, x, y = f:GetPoint( 1 )
		cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
		cfg.width, cfg.height = f:GetWidth(), f:GetHeight()
	end
	f:RegisterForDrag( "LeftButton" )
	f:SetScript( "OnDragStart", f.StartMoving )
	f:SetScript( "OnDragStop", function( self ) self:StopMovingOrSizing(); Save() end )
	f:HookScript( "OnHide", Save )

	-- Resize grip in the bottom-right corner (matches the other windows).
	local resize = CreateFrame( "Button", nil, f )
	resize:SetSize( 16, 16 )
	resize:SetPoint( "BOTTOMRIGHT", -5, 5 )
	resize:SetNormalTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up" )
	resize:SetPushedTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down" )
	resize:SetHighlightTexture( "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight" )
	resize:SetScript( "OnMouseDown", function() f:StartSizing( "BOTTOMRIGHT" ) end )
	resize:SetScript( "OnMouseUp", function() f:StopMovingOrSizing(); Save() end )

	function f.RestorePlacement()
		f:SetSize( cfg.width or width, cfg.height or height )
		f:ClearAllPoints()
		if cfg.point then
			f:SetPoint( cfg.point, UIParent, cfg.relPoint or cfg.point, cfg.x or 0, cfg.y or 0 )
		else
			f:SetPoint( "CENTER" )
		end
	end

	-- Intentionally NOT added to UISpecialFrames: Escape should not close the
	-- dice-game windows (close them with the X button instead).

	return f
end

-------------------------------------------------------------------------------
-- Shared die tooltip.
--
-- A parchment panel showing a die's weights (numbered boxes 1-6 with the weight
-- under each) and its flavour text. Used by both the inventory and the Farkle
-- play view so players can always see what a die does. Built once, lazily.
--
local tip, tipTitle, tipDesc, tipWeights

local TIP_TILE = {
	bgFile   = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function BuildTip()
	tip = CreateFrame( "Frame", "EmberhollowDieTip", UIParent, "BackdropTemplate" )
	tip:SetFrameStrata( "TOOLTIP" )
	tip:SetSize( 220, 140 )
	Me.StyleParchmentFrame( tip )
	tip:Hide()
	local tc = Me.TEXT_COLOR

	tipTitle = tip:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	tipTitle:SetPoint( "TOPLEFT", 14, -12 )
	tipTitle:SetPoint( "TOPRIGHT", -14, -12 )
	tipTitle:SetJustifyH( "LEFT" )

	tipWeights = {}
	for f = 1, 6 do
		local box = CreateFrame( "Frame", nil, tip, "BackdropTemplate" )
		box:SetSize( 22, 22 )
		box:SetPoint( "TOPLEFT", 14 + ( f - 1 ) * 32, -36 )
		box:SetBackdrop( TIP_TILE )
		box:SetBackdropColor( 0.15, 0.10, 0.06, 0.95 )
		box:SetBackdropBorderColor( 0.80, 0.64, 0.30, 1 )
		local n = box:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
		n:SetPoint( "CENTER" )
		n:SetText( f )
		n:SetTextColor( 1, 0.90, 0.50 )

		local w = tip:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
		w:SetPoint( "TOP", box, "BOTTOM", 0, -3 )
		w:SetTextColor( tc.r, tc.g, tc.b )
		tipWeights[f] = w
	end

	tipDesc = tip:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
	tipDesc:SetPoint( "TOPLEFT", 14, -82 )
	tipDesc:SetPoint( "TOPRIGHT", -14, -82 )
	tipDesc:SetJustifyH( "LEFT" )
	tipDesc:SetSpacing( 2 )
	tipDesc:SetTextColor( 0.85, 0.82, 0.74 )
end

-- Show the tooltip for `die`, anchored just to the right of `anchor` (a frame).
function Me.DiceGames_ShowDieTip( die, anchor )
	if not die then return end
	if not tip then BuildTip() end

	tipTitle:SetText( die.name or "Die" )
	for f = 1, 6 do
		local pct = math.floor( ( die.weights and die.weights[f] or 0 ) + 0.5 )
		tipWeights[f]:SetText( pct .. "%" )
	end
	tipDesc:SetText( die.desc or "" )

	tip:SetHeight( 82 + math.max( 12, tipDesc:GetStringHeight() ) + 14 )
	tip:ClearAllPoints()
	tip:SetPoint( "TOPLEFT", anchor or UIParent, "TOPRIGHT", 8, 0 )
	tip:Show()
end

function Me.DiceGames_HideDieTip()
	if tip then tip:Hide() end
end

-------------------------------------------------------------------------------
-- The hub window: a simple list of registered games. Picking one calls its
-- onPlay (and hides the hub, since the game opens its own window).
--
local hub          -- the hub frame (EmberhollowDiceGamesFrame)
local gameButtons  -- the per-game buttons, rebuilt by RefreshHub

local BTN_W   = 200
local BTN_H   = 30
local TOP_PAD = 44   -- below the title
local BTN_GAP = 8

function Me.DiceGames_RefreshHub()
	if not hub then return end

	gameButtons = gameButtons or {}

	for i, game in ipairs( Me.DiceGames ) do
		local b = gameButtons[i]
		if not b then
			b = CreateFrame( "Button", nil, hub, "UIPanelButtonTemplate" )
			b:SetSize( BTN_W, BTN_H )
			b:SetPoint( "TOP", 0, -TOP_PAD - ( i - 1 ) * ( BTN_H + BTN_GAP ) )
			gameButtons[i] = b
		end
		b:SetText( game.name )
		b:SetScript( "OnClick", function()
			hub:Hide()
			if game.onPlay then game.onPlay() end
		end )
		b:Show()
	end

	-- Hide any leftover buttons from a shorter list.
	for i = #Me.DiceGames + 1, #gameButtons do
		gameButtons[i]:Hide()
	end

	-- Grow the window to fit the list (with room for the footer blurb).
	local rows = math.max( 1, #Me.DiceGames )
	hub:SetHeight( TOP_PAD + rows * ( BTN_H + BTN_GAP ) + 52 )
end

function Me.DiceGames_Toggle()
	if not hub then return end
	if hub:IsShown() then
		hub:Hide()
	else
		Me.DiceGames_RefreshHub()
		hub:Show()
	end
end

-------------------------------------------------------------------------------
-- Build the hub and seed the RNG. Registered with Core's SafeInit.
--
function Me.DiceGames_Init()
	-- WoW seeds its own RNG; math.randomseed isn't available in the sandbox, so
	-- we just use math.random as-is.
	Me.db.diceGamesHub = Me.db.diceGamesHub or {}

	hub = Me.DiceGames_CreateWindow( "EmberhollowDiceGamesFrame", Me.db.diceGamesHub, 280, 160 )
	hub.TitleText:SetText( "Dice Games" )

	local tc = Me.TEXT_COLOR
	local blurb = hub:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
	blurb:SetPoint( "BOTTOMLEFT", 18, 16 )
	blurb:SetPoint( "BOTTOMRIGHT", -18, 16 )
	blurb:SetJustifyH( "CENTER" )
	blurb:SetText( "Pick a game." )
	blurb:SetTextColor( tc.r, tc.g, tc.b )

	hub.RestorePlacement()
	Me.DiceGames_RefreshHub()
end
