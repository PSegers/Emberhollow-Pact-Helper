-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Minimap button / launcher
-------------------------------------------------------------------------------
--
-- A button on the minimap (and a matching entry in Blizzard's addon
-- compartment) that opens the addon's windows:
--
--   Left-click          -> Options
--   Right-click         -> Marker names
--   Shift + right-click -> Cheat sheet
--
-- The minimap button is provided by LibDataBroker-1.1 + LibDBIcon-1.0 (vendored
-- under Libs/): the library owns the button's placement around the ring, the
-- drag-to-move behaviour and the hide/show state (stored in Me.db.minimap).
-- Toggle it with /eph minimap.
--

local _, Me = ...

local LDB       = LibStub and LibStub:GetLibrary( "LibDataBroker-1.1", true )
local LibDBIcon = LibStub and LibStub:GetLibrary( "LibDBIcon-1.0", true )

-- Unique name shared by the LDB data object and the LibDBIcon registration.
local OBJECT = "EmberhollowPactHelper"

-- The addon's own logo, reused for the button and the compartment entry.
local ICON = "Interface\\AddOns\\EmberhollowPactHelper\\EPHLogo.tga"

-------------------------------------------------------------------------------
-- Hover tooltip listing the click actions (shared by the LDB object and the
-- addon-compartment entry).
--
local function FillTooltip( tooltip )
	tooltip:AddLine( "Emberhollow Pact Helper" )
	tooltip:AddLine( "|cffffffffLeft-click|r  Options", 0.9, 0.8, 0.5 )
	tooltip:AddLine( "|cffffffffRight-click|r  Marker names", 0.9, 0.8, 0.5 )
	tooltip:AddLine( "|cffffffffShift + right-click|r  Cheat sheet", 0.9, 0.8, 0.5 )
end

-------------------------------------------------------------------------------
-- Show / hide the minimap button, remembering the choice. Called from
-- /eph minimap. LibDBIcon both flips the live button and persists db.hide.
--
function Me.Minimap_SetShown( show )
	Me.db.minimap.hide = not show
	if not LibDBIcon then return end
	if show then
		LibDBIcon:Show( OBJECT )
	else
		LibDBIcon:Hide( OBJECT )
	end
end

-------------------------------------------------------------------------------
-- Build the data object, register the minimap button and the compartment entry.
--
function Me.Minimap_Init()
	Me.db.minimap = Me.db.minimap or {}

	if not LDB or not LibDBIcon then
		Me.Print( "|cffff0000Minimap button unavailable (LibDataBroker / LibDBIcon failed to load).|r" )
		return
	end

	local dataobject = LDB:NewDataObject( OBJECT, {
		type = "launcher",
		icon = ICON,
		OnClick = function( _, mouseButton )
			Me.LauncherClick( mouseButton )
		end,
		OnTooltipShow = FillTooltip,
	} )

	-- LibDBIcon owns Me.db.minimap (its .hide / .minimapPos live there) and
	-- honours db.hide on register, so a hidden button stays hidden after login.
	LibDBIcon:Register( OBJECT, dataobject, Me.db.minimap )

	-- Blizzard's addon compartment (the dropdown by the minimap). Stock since
	-- 10.0; guard so older clients just skip it. registerForAnyClick lets the
	-- right-click actions work from the menu too.
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon( {
			text = "Emberhollow Pact Helper",
			icon = ICON,
			registerForAnyClick = true,
			func = function( ... )
				-- The mouse-button string's position in the args varies by
				-- client version, so sniff for it and default to left-click.
				local mouseButton = "LeftButton"
				for i = 1, select( "#", ... ) do
					local v = select( i, ... )
					if v == "LeftButton" or v == "RightButton" or v == "MiddleButton" then
						mouseButton = v
						break
					end
				end
				Me.LauncherClick( mouseButton )
			end,
			funcOnEnter = function( self )
				GameTooltip:SetOwner( self, "ANCHOR_LEFT" )
				FillTooltip( GameTooltip )
				GameTooltip:Show()
			end,
			funcOnLeave = function() GameTooltip:Hide() end,
		} )
	end
end
