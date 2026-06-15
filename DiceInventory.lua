-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Dice inventory
-------------------------------------------------------------------------------
--
-- Lets the player see every die in the catalogue (DiceData.lua), set how many
-- of each they own, and build the six-die "pool" the Farkle game rolls with.
--
--   * Each die has an owned count, 0-6, set with - / + buttons. Dice you don't
--     own (count 0) are greyed out. The regular die is always available.
--   * Hovering a die's name pops a tooltip: a row of numbered boxes (faces 1-6)
--     with that face's weight underneath, plus the die's flavour text.
--   * Your pool is six slots. You can't add more copies of a die than you own.
--     Click a pool slot to select it, then "Add" an owned die into it. The pool
--     is what the Farkle game uses on its next Start Game.
--
-- Opened from the Farkle menu's "Inventory" button (Me.DiceInventory_Open).
--

local _, Me = ...

local frame          -- the inventory window (EmberhollowDiceInventoryFrame)
local poolButtons    -- [1..6] pool-slot buttons
local rows           -- one row per die in the catalogue
local selectedSlot = 1

-- Every die shown in the list: the always-available regular die first, then the
-- rest of the catalogue (DiceData.lua) sorted alphabetically by name. Sorting a
-- fresh copy keeps Me.DICE_LIBRARY's own order untouched for everything else.
local function AllDice()
	local list = {}
	for _, d in ipairs( Me.DICE_LIBRARY or {} ) do
		list[#list + 1] = d
	end
	table.sort( list, function( a, b ) return a.name < b.name end )
	table.insert( list, 1, Me.REGULAR_DIE )   -- the unlimited regular die always heads the list
	return list
end

-------------------------------------------------------------------------------
-- Repaint the pool slots and the catalogue rows from saved state.
--
local function RefreshInventory()
	if not frame then return end

	for i = 1, 6 do
		local die = Me.DiceGames_GetDie( Me.db.dicePool[i] or "regular" )
		poolButtons[i]:SetText( i .. ". " .. die.name )
		if i == selectedSlot then
			poolButtons[i]:LockHighlight()
		else
			poolButtons[i]:UnlockHighlight()
		end
	end

	for _, row in ipairs( rows ) do
		local count = Me.DiceGames_GetOwnedCount( row.id )
		local owned = count > 0
		row.name:SetAlpha( owned and 1 or 0.35 )

		if row.id == "regular" then
			row.count:SetText( "\226\136\158" )   -- infinity: the regular die is unlimited
			row.minus:Hide()
			row.plus:Hide()
		else
			row.count:SetText( count )
			row.minus:Show()
			row.plus:Show()
			row.minus:SetEnabled( count > 0 )
			row.plus:SetEnabled( count < 6 )
		end

		-- Can add another copy to the pool? (regular is unlimited.)
		row.add:SetEnabled( row.id == "regular" or ( owned and Me.DiceGames_PoolCount( row.id ) < count ) )
	end
end

-------------------------------------------------------------------------------
-- Build one catalogue row inside the scroll child.
--
local ROW_H = 26

local function BuildRow( parent, die, index )
	local row = CreateFrame( "Frame", nil, parent )
	row:SetHeight( ROW_H )
	row:SetPoint( "TOPLEFT",  0, -( index - 1 ) * ROW_H )
	row:SetPoint( "TOPRIGHT", 0, -( index - 1 ) * ROW_H )
	row.id = die.id

	local tc = Me.TEXT_COLOR

	-- Hovering the row pops the weight / flavour tooltip for this die.
	row:EnableMouse( true )
	row:SetScript( "OnEnter", function() Me.DiceGames_ShowDieTip( die, frame ) end )
	row:SetScript( "OnLeave", Me.DiceGames_HideDieTip )

	-- "Add to selected pool slot" button on the far right.
	local add = CreateFrame( "Button", nil, row, "UIPanelButtonTemplate" )
	add:SetSize( 46, 20 )
	add:SetPoint( "RIGHT", -2, 0 )
	add:SetText( "Add" )
	add:SetScript( "OnClick", function()
		if Me.DiceGames_SetPoolSlot( selectedSlot, die.id ) then
			selectedSlot = ( selectedSlot % 6 ) + 1   -- advance to the next slot
			RefreshInventory()
		end
	end )
	row.add = add

	-- Owned-count stepper: [-] N [+].
	local plus = CreateFrame( "Button", nil, row, "UIPanelButtonTemplate" )
	plus:SetSize( 22, 20 )
	plus:SetPoint( "RIGHT", add, "LEFT", -8, 0 )
	plus:SetText( "+" )
	plus:SetScript( "OnClick", function()
		Me.DiceGames_SetOwnedCount( die.id, Me.DiceGames_GetOwnedCount( die.id ) + 1 )
		RefreshInventory()
	end )
	row.plus = plus

	local count = row:CreateFontString( nil, "OVERLAY", "GameFontHighlight" )
	count:SetPoint( "RIGHT", plus, "LEFT", -6, 0 )
	count:SetWidth( 18 )
	count:SetJustifyH( "CENTER" )
	count:SetTextColor( tc.r, tc.g, tc.b )
	row.count = count

	local minus = CreateFrame( "Button", nil, row, "UIPanelButtonTemplate" )
	minus:SetSize( 22, 20 )
	minus:SetPoint( "RIGHT", count, "LEFT", -6, 0 )
	minus:SetText( "-" )
	minus:SetScript( "OnClick", function()
		Me.DiceGames_SetOwnedCount( die.id, Me.DiceGames_GetOwnedCount( die.id ) - 1 )
		RefreshInventory()
	end )
	row.minus = minus

	local name = row:CreateFontString( nil, "OVERLAY", "GameFontHighlight" )
	name:SetPoint( "LEFT", 4, 0 )
	name:SetPoint( "RIGHT", minus, "LEFT", -8, 0 )
	name:SetJustifyH( "LEFT" )
	name:SetText( die.name )
	name:SetTextColor( tc.r, tc.g, tc.b )
	row.name = name

	return row
end

-------------------------------------------------------------------------------
-- Open / show the inventory.
--
function Me.DiceInventory_Open()
	if not frame then return end
	RefreshInventory()
	frame.RestorePlacement()
	frame:Show()
end

-------------------------------------------------------------------------------
-- Build the window. Registered with Core's SafeInit.
--
function Me.DiceInventory_Init()
	Me.db.diceInventoryWindow = Me.db.diceInventoryWindow or {}
	Me.db.diceOwned = Me.db.diceOwned or {}
	Me.db.dicePool  = Me.db.dicePool  or { "regular", "regular", "regular", "regular", "regular", "regular" }

	frame = Me.DiceGames_CreateWindow( "EmberhollowDiceInventoryFrame", Me.db.diceInventoryWindow, 440, 480 )
	frame.TitleText:SetText( "Dice Inventory" )
	frame:HookScript( "OnHide", Me.DiceGames_HideDieTip )
	local tc = Me.TEXT_COLOR

	-- Pool header.
	local poolHeader = frame:CreateFontString( nil, "OVERLAY", "GameFontNormal" )
	poolHeader:SetPoint( "TOPLEFT", 16, -38 )
	poolHeader:SetText( "Your pool (used in Farkle):" )

	-- Six pool slots, laid out 2 columns x 3 rows so the die names fit.
	poolButtons = {}
	local COL_W, ROW_STEP = 198, 28
	for i = 1, 6 do
		local col = ( i - 1 ) % 2
		local r   = math.floor( ( i - 1 ) / 2 )
		local b = CreateFrame( "Button", nil, frame, "UIPanelButtonTemplate" )
		b:SetSize( 192, 24 )
		b:SetPoint( "TOPLEFT", 16 + col * COL_W, -58 - r * ROW_STEP )
		b:RegisterForClicks( "LeftButtonUp", "RightButtonUp" )
		b:SetScript( "OnClick", function( _, mouse )
			if mouse == "RightButton" then
				Me.DiceGames_SetPoolSlot( i, "regular" )   -- right-click clears to regular
			else
				selectedSlot = i
			end
			RefreshInventory()
		end )
		poolButtons[i] = b
	end

	local hint = frame:CreateFontString( nil, "OVERLAY", "GameFontDisableSmall" )
	hint:SetPoint( "TOPLEFT", 16, -148 )
	hint:SetPoint( "TOPRIGHT", -16, -148 )
	hint:SetJustifyH( "LEFT" )
	hint:SetText( "Click a pool slot to select it, then Add an owned die. Right-click a slot to reset it. Hover a die's name for its odds." )

	-- Divider above the catalogue.
	local line = frame:CreateTexture( nil, "ARTWORK" )
	line:SetHeight( 1 )
	line:SetPoint( "TOPLEFT", 16, -176 )
	line:SetPoint( "TOPRIGHT", -16, -176 )
	line:SetColorTexture( tc.r, tc.g, tc.b, 0.25 )

	-- Scrolling catalogue of every die.
	local scroll = CreateFrame( "ScrollFrame", "EmberhollowDiceInventoryScroll", frame, "UIPanelScrollFrameTemplate" )
	scroll:SetPoint( "TOPLEFT", 16, -184 )
	scroll:SetPoint( "BOTTOMRIGHT", -32, 16 )

	local child = CreateFrame( "Frame", nil, scroll )
	child:SetSize( 1, 1 )
	scroll:SetScrollChild( child )

	-- Keep the row width matched to the scroll frame as the window resizes.
	scroll:SetScript( "OnSizeChanged", function( self, w )
		child:SetWidth( w )
	end )
	child:SetWidth( scroll:GetWidth() )

	rows = {}
	local list = AllDice()
	for index, die in ipairs( list ) do
		rows[index] = BuildRow( child, die, index )
	end
	child:SetHeight( #list * ROW_H )

	frame.RestorePlacement()
end
