-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Cheat sheet window
-------------------------------------------------------------------------------
--
-- A small, movable reference window you can page through with Previous / Next
-- arrows. The window's *layout* lives in CheatSheet.xml (PortraitFrameTemplate
-- gives us the border, title region and close (X) button); this file owns the
-- behaviour -- paging, dragging and the page contents.
--
-- Open / close it with  /eph cheatsheet  (Me.CheatSheet_Toggle).
--
-- The page contents below are placeholders. To fill in the real reference text
-- later, edit the PAGES table -- each entry is { title = ..., body = ... } and
-- `body` accepts the usual escapes (|cff...|r colour, |n newlines, textures).
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

-------------------------------------------------------------------------------
-- Small colour helpers for the page text. WoW colours inline text with
-- |cAARRGGBB ... |r escape codes, so we wrap snippets in named helpers to keep
-- the page bodies readable. The theme: Hope is the system's "good" die
-- (yellow/gold), Fear its "bad" die (purple); the rest are restrained accents.
--
local function colour( hex, s ) return "|cff" .. hex .. s .. "|r" end
local function Hope( s ) return colour( "ffd100", s ) end   -- yellow / gold
local function Fear( s ) return colour( "a335ee", s ) end   -- purple
local function Crit( s ) return colour( "ffe066", s ) end   -- bright gold
local function Good( s ) return colour( "40d040", s ) end   -- green  (success / safe)
local function Bad ( s ) return colour( "ff5040", s ) end   -- red    (miss / fail / hit)
local function Dmg ( s ) return colour( "ff8000", s ) end   -- orange (damage)
local function Head( s ) return colour( "66ccff", s ) end   -- light blue (sub-headers)

-- Join lines with WoW's |n newline (an empty string makes a blank line).
local function lines( ... ) return table.concat( { ... }, "|n" ) end

-------------------------------------------------------------------------------
-- The pages. Add, remove or reorder entries freely -- the nav adapts to #PAGES.
-- Each entry's `title` shows in the window's title bar; `body` is the content.
--
local PAGES = {
	{
		title = "Rolling",
		body  = lines(
			"Rolling is done with a " .. Head("2d12") .. ". The first die shown in the chat box is the " .. Hope("Hope") .. " die, the second the " .. Fear("Fear") .. " die.",
			"",
			"If " .. Hope("Hope") .. " > " .. Fear("Fear") .. "  \194\187  you rolled " .. Hope("with Hope") .. ".",
			"If " .. Fear("Fear") .. " > " .. Hope("Hope") .. "  \194\187  you rolled " .. Fear("with Fear") .. ".",
			"If " .. Hope("Hope") .. " = " .. Fear("Fear") .. "  \194\187  you've " .. Crit("critted") .. " (counts as rolling " .. Hope("with Hope") .. ").",
			"",
			"In this system there are thus five outcomes:",
			"Failure with " .. Fear("Fear") .. " (" .. Bad("FF") .. "): a really bad failure. You done fucked up!",
			"Failure with " .. Hope("Hope") .. " (" .. Bad("FH") .. "): you fail, but you can bounce back from this.",
			"Success with " .. Fear("Fear") .. " (" .. Good("SF") .. "): you succeed, but not perfectly. A consequence may still be attached.",
			"Success with " .. Hope("Hope") .. " (" .. Good("SH") .. "): you succeed with flying colours.",
			Crit("Crit") .. ": an exceptional performance! Or very lucky..."
		),
	},
	{
		title = "Attacking",
		body  = lines(
			Head("Attack Roll:") .. " 1d12 (" .. Hope("Hope") .. ") + 1d12 (" .. Fear("Fear") .. ") + ATK Modifier",
			"",
			Bad("FF")  .. "  \226\128\148  Miss!",
			Bad("FH")  .. "  \226\128\148  Miss!",
			Good("SF") .. "  \226\128\148  you deal " .. Dmg("1 DMG") .. ".",
			Good("SH") .. "  \226\128\148  you deal " .. Dmg("2 DMG") .. ".",
			Crit("Crit") .. "  \226\128\148  you deal " .. Dmg("3 DMG") .. "."
		),
	},
	{
		title = "Defending",
		body  = lines(
			Head("Defense Roll:") .. " 1d12 (" .. Hope("Hope") .. ") + 1d12 (" .. Fear("Fear") .. ") + DEF Modifier",
			"",
			Bad("FF")  .. "  \226\128\148  Take " .. Dmg("DMG") .. "!",
			Bad("FH")  .. "  \226\128\148  Take " .. Dmg("DMG") .. "!",
			Good("SF") .. "  \226\128\148  " .. Good("Safe!"),
			Good("SH") .. "  \226\128\148  " .. Good("Safe!"),
			Crit("Crit") .. "  \226\128\148  " .. Good("Safe!") .. " Deal " .. Dmg("1 DMG") .. " back!"
		),
	},
	{
		title = "Saving",
		body  = lines(
			"You can save someone from taking damage when:",
			"\194\183 you are not under attack yourself; " .. Hope("and"),
			"\194\183 you can feasibly help the person in question; " .. Hope("and"),
			"\194\183 you are not otherwise occupied with another action.",
			"",
			"A person can only be saved by " .. Bad("ONE") .. " other person per round!",
			"",
			Head("Save Roll:") .. " 1d12 (" .. Hope("Hope") .. ") + 1d12 (" .. Fear("Fear") .. ") + DEF Modifier",
			"",
			Bad("FF")  .. "  \226\128\148  Fail!",
			Bad("FH")  .. "  \226\128\148  Fail!",
			Good("SF") .. "  \226\128\148  you defend your target, but still take half " .. Dmg("DMG") .. " from the hit.",
			Good("SH") .. "  \226\128\148  you defend your target completely. Neither of you takes " .. Dmg("DMG") .. ".",
			Crit("Crit") .. "  \226\128\148  you save your target and deal " .. Dmg("1 DMG") .. " back."
		),
	},
}

local frame              -- the cheat-sheet window (EmberhollowCheatSheetFrame)
local currentPage = 1    -- which page is showing

-- Default window geometry, used until the player drags/resizes it themselves.
local DEFAULT_WIDTH  = 380
local DEFAULT_HEIGHT = 320
local MIN_WIDTH      = 300
local MIN_HEIGHT     = 220

-------------------------------------------------------------------------------
-- Persist the current point + size into Me.db so the window reopens exactly
-- where (and how big) the player last left it.
--
local function SavePlacement()
	if not frame then return end
	local cfg = Me.db.cheatSheet
	local point, _, relPoint, x, y = frame:GetPoint( 1 )
	cfg.point    = point
	cfg.relPoint = relPoint
	cfg.x        = x
	cfg.y        = y
	cfg.width    = frame:GetWidth()
	cfg.height   = frame:GetHeight()
end

-------------------------------------------------------------------------------
-- Restore the saved point + size (or fall back to a centred default).
--
local function RestorePlacement()
	if not frame then return end
	local cfg = Me.db.cheatSheet

	frame:SetSize( cfg.width or DEFAULT_WIDTH, cfg.height or DEFAULT_HEIGHT )

	frame:ClearAllPoints()
	if cfg.point then
		frame:SetPoint( cfg.point, UIParent, cfg.relPoint or cfg.point, cfg.x or 0, cfg.y or 0 )
	else
		frame:SetPoint( "CENTER" )
	end
end

-------------------------------------------------------------------------------
-- Paint the current page into the window and update the nav state.
--
local function RefreshPage()
	if not frame then return end

	local page = PAGES[currentPage]
	frame.TitleText:SetText( page and page.title or "Cheat Sheet" )
	frame.Body:SetText( page and page.body or "" )
	frame.PageNum:SetText( currentPage .. " / " .. #PAGES )

	-- Grey out the arrows at the ends so you can tell you've hit a boundary.
	frame.PrevButton:SetEnabled( currentPage > 1 )
	frame.NextButton:SetEnabled( currentPage < #PAGES )
end

-------------------------------------------------------------------------------
-- Step to another page, clamped to the valid range.
--
local function GoToPage( index )
	if index < 1 then index = 1 end
	if index > #PAGES then index = #PAGES end
	currentPage = index
	RefreshPage()
end

-------------------------------------------------------------------------------
-- Show / hide the cheat sheet. Called from the /eph cheatsheet command.
--
function Me.CheatSheet_Toggle()
	if not frame then return end   -- init failed / XML didn't load

	if frame:IsShown() then
		frame:Hide()
	else
		RefreshPage()
		frame:Show()
	end
end

-------------------------------------------------------------------------------
-- Wire up the XML-defined frame: dragging, button clicks, Escape-to-close.
--
function Me.CheatSheet_Init()
	frame = EmberhollowCheatSheetFrame
	if not frame then
		Me.Print( "|cffff0000Cheat sheet UI failed to load (CheatSheet.xml missing?).|r" )
		return
	end

	-- Where we stash the remembered position/size. Lazily created so we don't
	-- have to touch Core's DB_DEFAULTS.
	Me.db.cheatSheet = Me.db.cheatSheet or {}

	-- Drag the window around by grabbing anywhere on it; save where it lands.
	frame:SetClampedToScreen( true )
	frame:RegisterForDrag( "LeftButton" )
	frame:SetScript( "OnDragStart", frame.StartMoving )
	frame:SetScript( "OnDragStop", function( self )
		self:StopMovingOrSizing()
		SavePlacement()
	end )

	-- Make it resizable from the bottom-right grip, with a sensible floor.
	frame:SetResizable( true )
	if frame.SetResizeBounds then
		frame:SetResizeBounds( MIN_WIDTH, MIN_HEIGHT )
	elseif frame.SetMinResize then
		frame:SetMinResize( MIN_WIDTH, MIN_HEIGHT )
	end
	frame.ResizeButton:SetScript( "OnMouseDown", function()
		frame:StartSizing( "BOTTOMRIGHT" )
	end )
	frame.ResizeButton:SetScript( "OnMouseUp", function()
		frame:StopMovingOrSizing()
		SavePlacement()
	end )

	-- Also capture placement whenever it closes (Escape or the X button).
	frame:HookScript( "OnHide", SavePlacement )

	-- Close with Escape, like most Blizzard panels.
	tinsert( UISpecialFrames, "EmberhollowCheatSheetFrame" )

	-- Page-turn arrows.
	frame.PrevButton:SetScript( "OnClick", function()
		PlaySound( SOUNDKIT.IG_ABILITY_PAGE_TURN )
		GoToPage( currentPage - 1 )
	end )
	frame.NextButton:SetScript( "OnClick", function()
		PlaySound( SOUNDKIT.IG_ABILITY_PAGE_TURN )
		GoToPage( currentPage + 1 )
	end )

	RestorePlacement()
	RefreshPage()
end
