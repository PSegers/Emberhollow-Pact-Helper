-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Total RP 3 integration
-------------------------------------------------------------------------------
--
-- When Total RP 3 is installed, add a button to its toolbar (the row of RP
-- buttons it shows) that opens our windows, with the same clicks as the minimap
-- launcher:
--
--   Left-click          -> Options
--   Right-click         -> Marker names
--   Shift + right-click -> Cheat sheet
--
-- This is the only place the addon touches another addon's API, so it stays
-- entirely optional: if TRP isn't loaded the file does nothing. We register a
-- TRP3 "module" (the supported extension point) and add the toolbar button once
-- TRP's own toolbar exists. Pattern mirrors how other addons (e.g. Sippy Cup)
-- hook the TRP toolbar.
--
-- The toc lists totalRP3 under OptionalDeps so, when present, it loads before us
-- and TRP3_API is available here at file scope.
--

local _, Me = ...

if not C_AddOns.IsAddOnLoaded( "totalRP3" ) then return end
if not TRP3_API or not TRP3_API.module or not TRP3_Addon then return end

local function onStart()
	TRP3_API.RegisterCallback( TRP3_Addon, TRP3_Addon.Events.WORKFLOW_ON_LOADED, function()
		if not TRP3_API.toolbar then return end

		TRP3_API.toolbar.toolbarAddButton{
			id         = "trp3_emberhollow_pact_helper",
			-- TRP's toolbar resolves icons through its own pipeline (atlas name,
			-- file ID, or a Blizzard ICONS name) -- it can't load a loose addon
			-- file like our EPHLogo.tga, so we use a stock dice icon name here.
			-- (The minimap button, addon compartment and the .toc all use the
			-- real logo, since those take a texture path directly.)
			icon       = "inv_misc_dice_02",
			configText = "Emberhollow Pact Helper",
			tooltip    = "Emberhollow Pact Helper",
			tooltipSub = "Quick access to the Emberhollow Pact Helper windows.",
			tooltipInstructions = {
				{ "Click",               "Options" },
				{ "Right-click",         "Marker names" },
				{ "Shift + Right-click", "Cheat sheet" },
			},
			onClick = function( _, _, button )
				if Me.LauncherClick then Me.LauncherClick( button ) end
			end,
		}
	end )
end

TRP3_API.module.registerModule{
	name        = "Emberhollow Pact Helper",
	description = "Adds a toolbar button to open Emberhollow Pact Helper.",
	version     = Me.version,
	id          = "trp_emberhollow_pact_helper",
	onStart     = onStart,
	minVersion  = 3,
}
