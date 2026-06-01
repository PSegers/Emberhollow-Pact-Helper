-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Options panel
-------------------------------------------------------------------------------
--
-- A canvas options page registered under the game's Options > AddOns list (via
-- the retail Settings API, with a fallback to the old InterfaceOptions API).
-- Holds the feature toggles as checkboxes and -- the reason this exists -- a
-- colour picker for each of the Duality dice colours, so colourblind players
-- can recolour the crit / Hope / Fear highlight to something they can read.
--

local _, Me = ...

-------------------------------------------------------------------------------
-- A labelled checkbox bound to a getter / setter. Returns the button; call its
-- :Refresh() to sync the visible tick from the saved variable.
--
local function MakeCheck( parent, label, getter, setter )
	local cb = CreateFrame( "CheckButton", nil, parent, "UICheckButtonTemplate" )
	cb:SetSize( 26, 26 )

	local text = cb:CreateFontString( nil, "ARTWORK", "GameFontHighlight" )
	text:SetPoint( "LEFT", cb, "RIGHT", 2, 1 )
	text:SetText( label )

	cb:SetScript( "OnClick", function( self )
		setter( self:GetChecked() and true or false )
	end )

	cb.Refresh = function()
		cb:SetChecked( getter() and true or false )
	end

	return cb
end

-------------------------------------------------------------------------------
-- A colour swatch button next to a label. Clicking opens the standard colour
-- picker; the chosen colour is written back through setColor( r, g, b ). The
-- swatch's :UpdateTex() repaints it from the current saved colour.
--
local function MakeSwatch( parent, label, getColor, setColor )
	local swatch = CreateFrame( "Button", nil, parent )
	swatch:SetSize( 22, 22 )

	-- A black backing, with the colour drawn slightly inset to read as a border.
	local border = swatch:CreateTexture( nil, "BACKGROUND" )
	border:SetAllPoints()
	border:SetColorTexture( 0, 0, 0, 1 )

	local fill = swatch:CreateTexture( nil, "ARTWORK" )
	fill:SetPoint( "TOPLEFT", 2, -2 )
	fill:SetPoint( "BOTTOMRIGHT", -2, 2 )

	local text = swatch:CreateFontString( nil, "ARTWORK", "GameFontHighlight" )
	text:SetPoint( "LEFT", swatch, "RIGHT", 8, 0 )
	text:SetText( label )

	swatch.label = text

	swatch.UpdateTex = function()
		local c = getColor()
		fill:SetColorTexture( c.r, c.g, c.b )
	end
	swatch.UpdateTex()

	swatch:SetScript( "OnClick", function()
		local c = getColor()
		-- Remember the starting colour so Cancel can restore it; don't rely on
		-- the picker passing it back (that shape has changed between versions).
		local origR, origG, origB = c.r, c.g, c.b

		local info = {
			hasOpacity = false,
			r = origR, g = origG, b = origB,
			swatchFunc = function()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				setColor( r, g, b )
				swatch.UpdateTex()
			end,
			cancelFunc = function()
				setColor( origR, origG, origB )
				swatch.UpdateTex()
			end,
		}

		ColorPickerFrame:SetupColorPickerAndShow( info )
	end )

	return swatch
end

-------------------------------------------------------------------------------
function Me.Options_Init()
	local panel = CreateFrame( "Frame" )
	panel.name = "Emberhollow Pact Helper"

	local title = panel:CreateFontString( nil, "ARTWORK", "GameFontNormalLarge" )
	title:SetPoint( "TOPLEFT", 16, -16 )
	title:SetText( "Emberhollow Pact Helper" )

	local sub = panel:CreateFontString( nil, "ARTWORK", "GameFontHighlightSmall" )
	sub:SetPoint( "TOPLEFT", title, "BOTTOMLEFT", 0, -8 )
	sub:SetWidth( 520 )
	sub:SetJustifyH( "LEFT" )
	sub:SetText( "Roleplay dice rolling and a \"typing...\" indicator." )

	-- Forward declaration: the Duality checkbox enables/disables the swatches.
	local SetSwatchesEnabled
	local swatches = {}

	---------------------------------------------------------------------------
	-- Feature toggles.
	--
	local cbTyping = MakeCheck( panel, "Show the \"typing...\" indicator",
		function() return Me.db.typingEnabled end,
		function( v )
			Me.db.typingEnabled = v
			if Me.Typing_RefreshButton then Me.Typing_RefreshButton() end
		end )
	cbTyping:SetPoint( "TOPLEFT", sub, "BOTTOMLEFT", -2, -18 )

	local cbGroup = MakeCheck( panel, "Show plain-text rolls broadcast by the group",
		function() return Me.db.showGroupRolls end,
		function( v ) Me.db.showGroupRolls = v end )
	cbGroup:SetPoint( "TOPLEFT", cbTyping, "BOTTOMLEFT", 0, -8 )

	local cbDuality = MakeCheck( panel, "Daggerheart Duality dice colouring (a single 2d12)",
		function() return Me.db.dualityEnabled end,
		function( v )
			Me.db.dualityEnabled = v
			SetSwatchesEnabled( v )
		end )
	cbDuality:SetPoint( "TOPLEFT", cbGroup, "BOTTOMLEFT", 0, -8 )

	---------------------------------------------------------------------------
	-- Duality dice colours.
	--
	local hdr = panel:CreateFontString( nil, "ARTWORK", "GameFontNormal" )
	hdr:SetPoint( "TOPLEFT", cbDuality, "BOTTOMLEFT", 2, -18 )
	hdr:SetText( "Duality dice colours" )

	local hint = panel:CreateFontString( nil, "ARTWORK", "GameFontDisableSmall" )
	hint:SetPoint( "TOPLEFT", hdr, "BOTTOMLEFT", 0, -4 )
	hint:SetText( "Click a swatch to recolour that result." )

	-- Each swatch reads and writes one { r, g, b } colour table in the DB.
	local function ColorGetter( key )
		return function() return Me.db[key] end
	end
	local function ColorSetter( key )
		return function( r, g, b )
			local c = Me.db[key]
			c.r, c.g, c.b = r, g, b
		end
	end

	local swCrit = MakeSwatch( panel, "Critical (matching dice)",
		ColorGetter( "dualityCritColor" ), ColorSetter( "dualityCritColor" ) )
	swCrit:SetPoint( "TOPLEFT", hint, "BOTTOMLEFT", 0, -12 )

	local swHope = MakeSwatch( panel, "With Hope (higher first die)",
		ColorGetter( "dualityHopeColor" ), ColorSetter( "dualityHopeColor" ) )
	swHope:SetPoint( "TOPLEFT", swCrit, "BOTTOMLEFT", 0, -10 )

	local swFear = MakeSwatch( panel, "With Fear (higher second die)",
		ColorGetter( "dualityFearColor" ), ColorSetter( "dualityFearColor" ) )
	swFear:SetPoint( "TOPLEFT", swHope, "BOTTOMLEFT", 0, -10 )

	swatches = { swCrit, swHope, swFear }

	SetSwatchesEnabled = function( on )
		for _, s in ipairs( swatches ) do
			s:SetEnabled( on )
			s:SetAlpha( on and 1 or 0.4 )
			s.label:SetTextColor( on and 1 or 0.5, on and 1 or 0.5, on and 1 or 0.5 )
		end
	end

	---------------------------------------------------------------------------
	-- Sync everything from the saved variables whenever the page is shown.
	--
	panel:SetScript( "OnShow", function()
		cbTyping.Refresh()
		cbGroup.Refresh()
		cbDuality.Refresh()
		for _, s in ipairs( swatches ) do s.UpdateTex() end
		SetSwatchesEnabled( Me.db.dualityEnabled and true or false )
	end )

	---------------------------------------------------------------------------
	-- Register the page. Retail uses the Settings API; fall back to the old
	-- InterfaceOptions API on clients that still have it.
	--
	if Settings and Settings.RegisterCanvasLayoutCategory then
		local category = Settings.RegisterCanvasLayoutCategory( panel, panel.name )
		category.ID = panel.name
		Settings.RegisterAddOnCategory( category )
		Me.optionsCategory = category
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory( panel )
		Me.optionsPanel = panel
	end
end

-------------------------------------------------------------------------------
-- Open our options page (used by "/eph options").
--
function Me.Options_Open()
	if Settings and Settings.OpenToCategory and Me.optionsCategory then
		Settings.OpenToCategory( Me.optionsCategory:GetID() )
	elseif InterfaceOptionsFrame_OpenToCategory and Me.optionsPanel then
		-- Called twice on purpose: a long-standing quirk where the first call
		-- only scrolls the list to the panel.
		InterfaceOptionsFrame_OpenToCategory( Me.optionsPanel )
		InterfaceOptionsFrame_OpenToCategory( Me.optionsPanel )
	else
		Me.Print( "Open Game Menu > Options > AddOns > Emberhollow Pact Helper." )
	end
end
