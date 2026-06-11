-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Farkle
-------------------------------------------------------------------------------
--
-- A solo, push-your-luck dice game played with six dice. Each action (Roll /
-- Pass / a bust) is announced to those around you as a plain /emote, so a group
-- can play socially -- everyone reads the results and tracks their own score.
--
-- Rules implemented here:
--   * Roll six dice. Banked dice are set aside; you reroll the rest.
--   * You must set aside at least one scoring die before you may roll on or pass.
--   * Pass: this turn's points are locked into your total and can't be lost.
--   * Bust: a roll with no scoring dice loses everything banked this turn.
--   * Hot dice: bank all six and you reroll all six, the turn continuing.
--
-- Scoring:
--   single 1 = 100, single 5 = 50
--   three of a kind = 100 * face  (three 1s = 1000)
--   each die past the third doubles the trio's value (four 4s = 800, five = 1600)
--   straight 1-6 = 1500, partial 1-5 = 500, partial 2-6 = 750
--
-- The window starts on a small menu (Start Game / Inventory); Start Game swaps
-- in the play view. Custom / weighted dice and the inventory come later -- the
-- dice are already chosen through a definition table (DICE) so that work just
-- swaps which definitions fill the six slots.
--
-- Opened from the Dice Games hub, or directly with  /eph farkle.
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

-------------------------------------------------------------------------------
-- Scoring engine.
--
-- ScoreSelection( faces ): the points for setting aside exactly `faces`, but
-- only if EVERY die in the selection takes part in a scoring combo. Returns the
-- point value (0 for an empty selection), or nil if the selection includes a
-- die that scores nothing (so the UI can reject it and Roll/Pass stay locked).
--
local function ScoreSelection( faces )
	local n = #faces
	if n == 0 then return 0 end

	local count = { 0, 0, 0, 0, 0, 0 }
	for _, f in ipairs( faces ) do
		count[f] = count[f] + 1
	end

	-- Straights are the only way an otherwise non-scoring spread (e.g. a 2, 3
	-- and 4) becomes a legal selection, so they're checked first.
	if n == 6 then
		local full = true
		for f = 1, 6 do
			if count[f] ~= 1 then full = false break end
		end
		if full then return 1500 end
	elseif n == 5 then
		if count[1] == 1 and count[2] == 1 and count[3] == 1 and count[4] == 1 and count[5] == 1 and count[6] == 0 then
			return 500   -- partial straight 1-5
		end
		if count[2] == 1 and count[3] == 1 and count[4] == 1 and count[5] == 1 and count[6] == 1 and count[1] == 0 then
			return 750   -- partial straight 2-6
		end
	end

	-- Otherwise: trios (and bigger) first, then leftover 1s / 5s.
	local pts = 0
	for face = 1, 6 do
		if count[face] >= 3 then
			local base = ( face == 1 ) and 1000 or face * 100
			local mult = 1
			for _ = 4, count[face] do mult = mult * 2 end   -- each die past three doubles
			pts = pts + base * mult
			count[face] = 0
		end
	end

	pts = pts + count[1] * 100 + count[5] * 50
	count[1], count[5] = 0, 0

	-- Anything still left is a selected die that scores nothing -> illegal.
	for face = 1, 6 do
		if count[face] > 0 then return nil end
	end
	return pts
end

-- Does this freshly-rolled set contain ANY scoring option? (If not, it's a
-- bust.) Straights always include a 1 or 5, so they're covered implicitly.
local function HasAnyScore( faces )
	local count = { 0, 0, 0, 0, 0, 0 }
	for _, f in ipairs( faces ) do
		count[f] = count[f] + 1
	end
	if count[1] > 0 or count[5] > 0 then return true end
	for f = 1, 6 do
		if count[f] >= 3 then return true end
	end
	return false
end

-------------------------------------------------------------------------------
-- Game state. A die slot is { value = 1-6 or nil, state = ... }:
--   "empty"    -- no value yet (before the first roll of a turn)
--   "active"   -- just rolled, may be rerolled or banked
--   "selected" -- player clicked Bank this roll (counts toward the live preview)
--   "set"      -- banked on an earlier roll this turn; locked aside
--
local F = {
	total  = 0,      -- points safely banked across turns
	banked = 0,      -- points locked THIS turn from dice already set aside
	rolled = false,  -- have the dice been rolled at least once this turn?
	await  = false,  -- a scoring roll is on the table, waiting for a selection
	message = nil,   -- transient line shown before the next roll (pass / bust)
	dice   = {},     -- [1..6] slots
}

-- The six dice in play. Refreshed from the player's pool (DiceGames.lua) at the
-- start of each game; defaults to six regular dice until then.
local DICE = { Me.REGULAR_DIE, Me.REGULAR_DIE, Me.REGULAR_DIE, Me.REGULAR_DIE, Me.REGULAR_DIE, Me.REGULAR_DIE }

for i = 1, 6 do F.dice[i] = { value = nil, state = "empty" } end

local function FacesByState( state )
	local t = {}
	for i = 1, 6 do
		if F.dice[i].state == state then t[#t + 1] = F.dice[i].value end
	end
	return t
end

-- A sorted, comma-joined face list for the emotes ("1, 5, 5").
local function ListFaces( faces )
	local copy = { unpack( faces ) }
	table.sort( copy )
	return table.concat( copy, ", " )
end

local function DieWord( n )
	return n .. ( n == 1 and " die" or " dice" )
end

-------------------------------------------------------------------------------
-- UI handles, built in Me.Farkle_Init.
--
local frame        -- the Farkle window (EmberhollowFarkleFrame)
local menuPanel    -- Start Game / Inventory view
local gamePanel    -- the play view
local tiles        -- [1..6] die tiles, each with .num and .bank
local totalFS, turnFS, previewFS
local rollBtn, passBtn

-------------------------------------------------------------------------------
-- Announce an action to those around the player (no colour, third person so it
-- reads naturally after the player's name, like "<Name> rolls six dice: ...").
--
local function Emote( msg )
	SendChatMessage( msg, "EMOTE" )
end

-------------------------------------------------------------------------------
-- Repaint the dice tiles, scores, preview line and button states.
--
local TILE = {
	empty    = { bg = { 0.10, 0.07, 0.04, 0.55 }, border = { 0.40, 0.34, 0.24, 0.6 }, text = { 0.5, 0.45, 0.35 } },
	active   = { bg = { 0.15, 0.10, 0.06, 0.95 }, border = { 0.80, 0.64, 0.30, 1 }, text = { 0.98, 0.95, 0.88 } },
	selected = { bg = { 0.28, 0.21, 0.07, 1.00 }, border = { 1.00, 0.85, 0.35, 1 }, text = { 1.00, 0.90, 0.50 } },
	set      = { bg = { 0.08, 0.06, 0.04, 0.95 }, border = { 0.38, 0.30, 0.20, 0.9 }, text = { 0.55, 0.50, 0.40 } },
}

local function Refresh()
	if not frame then return end

	for i = 1, 6 do
		local d  = F.dice[i]
		local t  = tiles[i]
		local sk = TILE[d.state] or TILE.empty

		t:SetBackdropColor( sk.bg[1], sk.bg[2], sk.bg[3], sk.bg[4] )
		t:SetBackdropBorderColor( sk.border[1], sk.border[2], sk.border[3], sk.border[4] )
		t.num:SetText( d.value and tostring( d.value ) or "" )
		t.num:SetTextColor( sk.text[1], sk.text[2], sk.text[3] )

		-- Name comes from the die definition, so custom dice show their own name.
		t.name:SetText( ( DICE[i] and DICE[i].name ) or "Die" )
		t.name:SetTextColor( sk.text[1], sk.text[2], sk.text[3] )

		-- Only active/selected dice carry a Bank toggle.
		if d.state == "active" or d.state == "selected" then
			t.bank:Show()
			t.bank:SetText( d.state == "selected" and "Banked" or "Bank" )
		else
			t.bank:Hide()
		end
	end

	local sel      = FacesByState( "selected" )
	local selScore = ScoreSelection( sel )
	local turnNow  = F.banked + ( ( selScore and selScore > 0 ) and selScore or 0 )

	totalFS:SetText( "Total score: " .. F.total )
	turnFS:SetText( "This turn: " .. turnNow )

	local canProceed = false
	if not F.rolled then
		previewFS:SetText( F.message or "Press Roll to begin your turn." )
		rollBtn:SetText( "Roll" )
		rollBtn:Enable()
		passBtn:Disable()
	else
		if #sel == 0 then
			previewFS:SetText( "Set aside at least one scoring die to continue." )
		elseif selScore == nil then
			previewFS:SetText( "|cffff6060That selection includes a non-scoring die.|r" )
		else
			previewFS:SetText( "Banking " .. ListFaces( sel ) .. "  =  " .. selScore .. " pts" )
			canProceed = true
		end
		rollBtn:SetText( "Roll" )
		rollBtn:SetEnabled( canProceed )
		passBtn:SetEnabled( canProceed )
	end
end

-------------------------------------------------------------------------------
-- Toggle a die between active and selected (banked-this-roll) when clicked.
--
local function ToggleDie( i )
	local d = F.dice[i]
	if d.state == "active" then
		d.state = "selected"
	elseif d.state == "selected" then
		d.state = "active"
	else
		return   -- empty / set dice aren't selectable
	end
	Refresh()
end

-------------------------------------------------------------------------------
-- Reset everything for a brand-new turn (keeps the running total).
--
local function NewTurn()
	F.banked = 0
	F.rolled = false
	F.await  = false
	for i = 1, 6 do
		F.dice[i].value = nil
		F.dice[i].state = "empty"
	end
end

-------------------------------------------------------------------------------
-- Lock the currently-selected dice into this turn's banked score and set them
-- aside. Returns the sorted faces banked and the points scored.
--
local function CommitSelection()
	local sel = FacesByState( "selected" )
	local pts = ScoreSelection( sel ) or 0
	F.banked = F.banked + pts
	for i = 1, 6 do
		if F.dice[i].state == "selected" then F.dice[i].state = "set" end
	end
	local copy = { unpack( sel ) }
	table.sort( copy )
	return copy, pts
end

-------------------------------------------------------------------------------
-- The Roll button: bank the current selection (if any), then reroll the dice
-- still in play -- or, if all six are now set aside, reroll all six (hot dice).
-- Ends the turn with a bust if the new roll has no scoring option.
--
local function DoRoll()
	F.message = nil

	-- Bank whatever is selected from the roll on the table.
	local bankedFaces, bankedPts
	if F.await then
		if ScoreSelection( FacesByState( "selected" ) ) == nil or #FacesByState( "selected" ) == 0 then
			return   -- button shouldn't be live, but never bank an illegal set
		end
		bankedFaces, bankedPts = CommitSelection()
	end

	-- Which dice still need rolling? (Those left active, i.e. not set aside.)
	local toRoll = {}
	for i = 1, 6 do
		if F.dice[i].state ~= "set" then toRoll[#toRoll + 1] = i end
	end

	-- Hot dice: everything was banked -> the whole set comes back into play.
	local hot = false
	if #toRoll == 0 then
		hot = true
		for i = 1, 6 do F.dice[i].state, F.dice[i].value = "empty", nil end
		toRoll = { 1, 2, 3, 4, 5, 6 }
	end

	for _, i in ipairs( toRoll ) do
		F.dice[i].value = Me.RollDie( DICE[i] )
		F.dice[i].state = "active"
	end
	F.rolled = true

	local rolled = FacesByState( "active" )

	-- Compose the emote: optional bank, the new roll, and the outcome.
	local parts = {}
	if bankedFaces then
		parts[#parts + 1] = "banks " .. table.concat( bankedFaces, ", " ) .. " (" .. bankedPts .. ")"
	end
	if hot then
		parts[#parts + 1] = "rolls all " .. DieWord( #rolled ) .. " anew: " .. ListFaces( rolled )
	elseif bankedFaces then
		parts[#parts + 1] = "rerolls " .. DieWord( #rolled ) .. ": " .. ListFaces( rolled )
	else
		parts[#parts + 1] = "rolls " .. DieWord( #rolled ) .. ": " .. ListFaces( rolled )
	end

	if not HasAnyScore( rolled ) then
		-- Bust: lose this turn's banked points (the total is unchanged).
		local lost = F.banked
		parts[#parts + 1] = ( lost > 0 ) and ( "Farkle! Loses " .. lost .. " points this turn" ) or "Farkle! No scoring dice"
		parts[#parts + 1] = "(total: " .. F.total .. ")"
		Emote( table.concat( parts, ", " ) .. "." )

		NewTurn()
		F.message = "Farkle! Press Roll to start a new turn."
	else
		F.await = true
		parts[#parts + 1] = "(turn: " .. F.banked .. ")"
		Emote( table.concat( parts, ", " ) .. "." )
	end

	Refresh()
end

-------------------------------------------------------------------------------
-- The Pass button: bank the current selection, lock the turn into the total and
-- announce it, then reset for the next turn.
--
local function DoPass()
	if not F.await then return end
	if ScoreSelection( FacesByState( "selected" ) ) == nil or #FacesByState( "selected" ) == 0 then
		return
	end

	local bankedFaces, bankedPts = CommitSelection()
	local turnTotal = F.banked
	F.total = F.total + turnTotal

	Emote( "banks " .. table.concat( bankedFaces, ", " ) .. " (" .. bankedPts .. ") and passes, scoring "
		.. turnTotal .. " points this turn (total: " .. F.total .. ")." )

	NewTurn()
	F.message = "Passed. Press Roll to begin your next turn."
	Refresh()
end

-------------------------------------------------------------------------------
-- Switch the window between the menu and the play view.
--
local function ShowMenu()
	gamePanel:Hide()
	menuPanel:Show()
	frame.TitleText:SetText( "Farkle" )
end

local function StartGame()
	F.total = 0
	NewTurn()
	F.message = nil

	-- Pull in the player's current dice pool (special dice replace regulars).
	if Me.DiceGames_GetPool then
		local pool = Me.DiceGames_GetPool()
		for i = 1, 6 do DICE[i] = pool[i] or Me.REGULAR_DIE end
	end

	menuPanel:Hide()
	gamePanel:Show()
	frame.TitleText:SetText( "Farkle" )
	Refresh()
end

-------------------------------------------------------------------------------
-- Open the Farkle window (on its menu). Called from the hub or /eph farkle.
--
function Me.Farkle_Open()
	if not frame then return end
	ShowMenu()
	frame.RestorePlacement()
	frame:Show()
end

-------------------------------------------------------------------------------
-- Build one die row: a value tile, the die's name, and a Bank toggle. Stacking
-- the dice vertically (rather than in a row) leaves room for each die's name,
-- so the player can see exactly which dice they're keeping or rerolling.
--
local TILE_BACKDROP = {
	bgFile   = "Interface\\Buttons\\WHITE8X8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12,
	insets   = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TILE_SIZE = 36
local ROW_H     = 42   -- vertical spacing between die rows
local ROW_TOP   = 36   -- y-offset of the first row inside the play view

local function BuildRow( parent, i )
	local row = CreateFrame( "Frame", nil, parent )
	row:SetHeight( TILE_SIZE )
	row:SetPoint( "TOPLEFT",  parent, "TOPLEFT",  16, -ROW_TOP - ( i - 1 ) * ROW_H )
	row:SetPoint( "TOPRIGHT", parent, "TOPRIGHT", -16, -ROW_TOP - ( i - 1 ) * ROW_H )

	-- The value tile (clickable to bank/unbank, hover to see the die's odds).
	local tile = CreateFrame( "Button", nil, row, "BackdropTemplate" )
	tile:SetSize( TILE_SIZE, TILE_SIZE )
	tile:SetPoint( "LEFT", 0, 0 )
	tile:SetBackdrop( TILE_BACKDROP )
	tile:SetScript( "OnClick", function() ToggleDie( i ) end )
	tile:SetScript( "OnEnter", function() Me.DiceGames_ShowDieTip( DICE[i], frame ) end )
	tile:SetScript( "OnLeave", function() Me.DiceGames_HideDieTip() end )

	local num = tile:CreateFontString( nil, "OVERLAY", "GameFontNormalHuge" )
	num:SetPoint( "CENTER" )
	tile.num = num

	-- The die's name, to the right of the tile.
	local name = row:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	name:SetPoint( "LEFT", tile, "RIGHT", 12, 0 )
	name:SetJustifyH( "LEFT" )
	tile.name = name

	-- Bank toggle on the right edge of the row.
	local bank = CreateFrame( "Button", nil, row, "UIPanelButtonTemplate" )
	bank:SetSize( 64, 22 )
	bank:SetPoint( "RIGHT", 0, 0 )
	bank:SetText( "Bank" )
	bank:SetScript( "OnClick", function() ToggleDie( i ) end )
	tile.bank = bank

	return tile
end

-------------------------------------------------------------------------------
-- The scoring sheet: a reference window listing every combination, the dice
-- that make it (as small numbered tiles matching the play view) and the points
-- it scores. Opened by the "?" button, built lazily on first use.
--
local scoreFrame
local MINI = 18   -- mini-die size on the sheet

local function MiniDie( parent, face )
	local d = CreateFrame( "Frame", nil, parent, "BackdropTemplate" )
	d:SetSize( MINI, MINI )
	d:SetBackdrop( TILE_BACKDROP )
	d:SetBackdropColor( 0.15, 0.10, 0.06, 0.95 )
	d:SetBackdropBorderColor( 0.80, 0.64, 0.30, 1 )
	local n = d:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
	n:SetPoint( "CENTER" )
	n:SetText( face )
	n:SetTextColor( 1, 0.90, 0.50 )
	return d
end

local function BuildScoringSheet()
	Me.db.farkleScoreWindow = Me.db.farkleScoreWindow or {}
	scoreFrame = Me.DiceGames_CreateWindow( "EmberhollowFarkleScoreFrame", Me.db.farkleScoreWindow, 340, 432 )
	scoreFrame.TitleText:SetText( "Farkle Scoring" )
	local tc = Me.TEXT_COLOR

	local DICE_X  = 120    -- left edge of the dice column
	local SCORE_X = -16    -- right inset for the score column

	local function Cell( anchor, inset, yy, font, text, color )
		local fs = scoreFrame:CreateFontString( nil, "OVERLAY", font )
		fs:SetPoint( anchor, inset, yy )
		fs:SetText( text )
		if color then fs:SetTextColor( color.r, color.g, color.b ) end
		return fs
	end
	local function Dice( faces, yy )
		for k, face in ipairs( faces ) do
			MiniDie( scoreFrame, face ):SetPoint( "TOPLEFT", DICE_X + ( k - 1 ) * ( MINI + 3 ), yy - 1 )
		end
	end

	local y = -38

	-- Column headers + divider.
	Cell( "TOPLEFT", 16, y, "GameFontNormal", "Combination" )
	Cell( "TOPLEFT", DICE_X, y, "GameFontNormal", "Dice" )
	Cell( "TOPRIGHT", SCORE_X, y, "GameFontNormal", "Score" )
	y = y - 20

	local line = scoreFrame:CreateTexture( nil, "ARTWORK" )
	line:SetHeight( 1 )
	line:SetPoint( "TOPLEFT", 16, y + 4 )
	line:SetPoint( "TOPRIGHT", -16, y + 4 )
	line:SetColorTexture( tc.r, tc.g, tc.b, 0.25 )
	y = y - 8

	local function Row( label, faces, score )
		Cell( "TOPLEFT", 16, y, "GameFontHighlight", label, tc )
		Dice( faces, y )
		Cell( "TOPRIGHT", SCORE_X, y, "GameFontHighlight", tostring( score ), tc )
		y = y - 24
	end
	local function Note( text, gap )
		local fs = scoreFrame:CreateFontString( nil, "OVERLAY", "GameFontDisableSmall" )
		fs:SetPoint( "TOPLEFT", 18, y )
		fs:SetPoint( "TOPRIGHT", -16, y )
		fs:SetJustifyH( "LEFT" )
		fs:SetText( text )
		y = y - ( gap or 18 )
	end

	Row( "Each 1", { 1 }, 100 )
	Row( "Each 5", { 5 }, 50 )
	Note( "A single 1 or 5 adds on to any combination." )

	Row( "Three 1s", { 1, 1, 1 }, 1000 )
	Row( "Three 2s", { 2, 2, 2 }, 200 )
	Row( "Three 3s", { 3, 3, 3 }, 300 )
	Row( "Three 4s", { 4, 4, 4 }, 400 )
	Row( "Three 5s", { 5, 5, 5 }, 500 )
	Row( "Three 6s", { 6, 6, 6 }, 600 )
	Note( "Each die past the third doubles the value (four 2s = 400, five = 800).", 28 )

	Row( "Straight 1-5", { 1, 2, 3, 4, 5 }, 500 )
	Row( "Straight 2-6", { 2, 3, 4, 5, 6 }, 750 )
	Row( "Straight 1-6", { 1, 2, 3, 4, 5, 6 }, 1500 )

	scoreFrame.RestorePlacement()
end

function Me.Farkle_ToggleScoring()
	if not scoreFrame then BuildScoringSheet() end
	if scoreFrame:IsShown() then
		scoreFrame:Hide()
	else
		scoreFrame.RestorePlacement()
		scoreFrame:Show()
	end
end

-------------------------------------------------------------------------------
-- Build the window and wire it up. Registered with Core's SafeInit.
--
function Me.Farkle_Init()
	Me.db.farkleWindow = Me.db.farkleWindow or {}

	frame = Me.DiceGames_CreateWindow( "EmberhollowFarkleFrame", Me.db.farkleWindow, 320, 430 )
	frame.TitleText:SetText( "Farkle" )
	frame:HookScript( "OnHide", Me.DiceGames_HideDieTip )
	local tc = Me.TEXT_COLOR

	---------------------------------------------------------------------------
	-- Menu view: Start Game / Inventory, with a short blurb.
	---------------------------------------------------------------------------
	menuPanel = CreateFrame( "Frame", nil, frame )
	menuPanel:SetPoint( "TOPLEFT", 0, -40 )
	menuPanel:SetPoint( "BOTTOMRIGHT", 0, 0 )

	local startBtn = CreateFrame( "Button", nil, menuPanel, "UIPanelButtonTemplate" )
	startBtn:SetSize( 200, 30 )
	startBtn:SetPoint( "TOP", 0, -16 )
	startBtn:SetText( "Start Game" )
	startBtn:SetScript( "OnClick", StartGame )

	local invBtn = CreateFrame( "Button", nil, menuPanel, "UIPanelButtonTemplate" )
	invBtn:SetSize( 200, 30 )
	invBtn:SetPoint( "TOP", startBtn, "BOTTOM", 0, -10 )
	invBtn:SetText( "Inventory" )
	invBtn:SetScript( "OnClick", function()
		if Me.DiceInventory_Open then Me.DiceInventory_Open() end
	end )

	local menuBlurb = menuPanel:CreateFontString( nil, "OVERLAY", "GameFontHighlightSmall" )
	menuBlurb:SetPoint( "TOPLEFT", 24, -100 )
	menuBlurb:SetPoint( "TOPRIGHT", -24, -100 )
	menuBlurb:SetJustifyH( "CENTER" )
	menuBlurb:SetText( "Roll six dice, set aside the scorers, then push your luck or pass. Each roll and pass is announced as an /emote." )
	menuBlurb:SetTextColor( tc.r, tc.g, tc.b )

	---------------------------------------------------------------------------
	-- Play view: scores, six dice tiles, a preview line and Roll / Pass.
	---------------------------------------------------------------------------
	gamePanel = CreateFrame( "Frame", nil, frame )
	gamePanel:SetPoint( "TOPLEFT", 0, -36 )
	gamePanel:SetPoint( "BOTTOMRIGHT", 0, 0 )
	gamePanel:Hide()

	totalFS = gamePanel:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	totalFS:SetPoint( "TOPLEFT", 20, -6 )
	totalFS:SetTextColor( tc.r, tc.g, tc.b )

	turnFS = gamePanel:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	turnFS:SetPoint( "TOPRIGHT", -20, -6 )
	turnFS:SetTextColor( tc.r, tc.g, tc.b )

	local line = gamePanel:CreateTexture( nil, "ARTWORK" )
	line:SetHeight( 1 )
	line:SetPoint( "TOPLEFT", 18, -24 )
	line:SetPoint( "TOPRIGHT", -18, -24 )
	line:SetColorTexture( tc.r, tc.g, tc.b, 0.25 )

	tiles = {}
	for i = 1, 6 do
		tiles[i] = BuildRow( gamePanel, i )
	end

	previewFS = gamePanel:CreateFontString( nil, "OVERLAY", "GameFontHighlight" )
	previewFS:SetPoint( "TOP", 0, -300 )
	previewFS:SetTextColor( tc.r, tc.g, tc.b )

	rollBtn = CreateFrame( "Button", nil, gamePanel, "UIPanelButtonTemplate" )
	rollBtn:SetSize( 100, 26 )
	rollBtn:SetPoint( "BOTTOM", -58, 14 )
	rollBtn:SetText( "Roll" )
	rollBtn:SetScript( "OnClick", DoRoll )

	passBtn = CreateFrame( "Button", nil, gamePanel, "UIPanelButtonTemplate" )
	passBtn:SetSize( 100, 26 )
	passBtn:SetPoint( "BOTTOM", 58, 14 )
	passBtn:SetText( "Pass" )
	passBtn:SetScript( "OnClick", DoPass )

	-- A "?" button (bottom-left) opens the Farkle scoring sheet.
	local helpBtn = CreateFrame( "Button", nil, gamePanel, "UIPanelButtonTemplate" )
	helpBtn:SetSize( 26, 22 )
	helpBtn:SetPoint( "BOTTOMLEFT", 14, 14 )
	helpBtn:SetText( "?" )
	helpBtn:SetScript( "OnClick", function() Me.Farkle_ToggleScoring() end )

	frame.RestorePlacement()

	-- Register with the hub so it appears in the games list.
	Me.DiceGames_Register{
		id     = "farkle",
		name   = "Farkle",
		blurb  = "Push-your-luck dice.",
		onPlay = Me.Farkle_Open,
	}
end
