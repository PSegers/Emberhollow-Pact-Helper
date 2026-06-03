-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- "Typing..." indicator
-------------------------------------------------------------------------------
--
-- The UI is built entirely in Lua (no XML).
--
-- While you're composing an IC message in say/emote/party/raid, a small toast
-- appears above your chat box telling your group "<Name> is typing...". A chat
-- button lets you flag a *longer* post manually (it stays lit until you toggle
-- it off again), which is handy when you step away mid-paragraph.
--

local _, Me = ...   -- ... is (addonName, addonTable); we want the shared table

-- Channels we consider "in-character chatter" worth announcing.
local TRACKED_CHANNELS = {
	SAY           = true,
	EMOTE         = true,
	YELL          = true,
	PARTY         = true,
	RAID          = true,
	RAID_WARNING  = true,
}

Me.WhoIsTyping = {}     -- ordered list of names currently typing

local typingFrame       -- the toast that shows "<Name> is typing..."
local typingButton      -- the manual toggle button
local selfTyping = false   -- our last-broadcast typing state

-------------------------------------------------------------------------------
-- Broadcast our typing state to the group.
--
local function SendTypingUpdate( typing )
	Me.SendComm( "T", typing )
end

-------------------------------------------------------------------------------
-- Show / refresh the toast based on who's typing, or fade it out when nobody is.
--
local function RefreshToast()
	if #Me.WhoIsTyping > 0 then
		local text = Me.WhoIsTyping[1]
		local plural = " is"

		if #Me.WhoIsTyping > 3 then
			text = "Several people"
			plural = " are"
		elseif #Me.WhoIsTyping > 1 then
			plural = " are"
			for i = 2, #Me.WhoIsTyping do
				if i == #Me.WhoIsTyping then
					if #Me.WhoIsTyping > 2 then
						text = text .. ", and " .. Me.WhoIsTyping[i]
					else
						text = text .. " and " .. Me.WhoIsTyping[i]
					end
				else
					text = text .. ", " .. Me.WhoIsTyping[i]
				end
			end
		end

		text = "|TInterface/GossipFrame/ChatBubbleGossipIcon:16|t " .. text .. plural .. " typing..."
		typingFrame.Message:SetText( text )

		typingFrame:Show()
		if typingFrame:GetAlpha() < 1 then
			UIFrameFadeIn( typingFrame, 0.3, typingFrame:GetAlpha(), 1 )
		end
	else
		if typingFrame:IsShown() then
			UIFrameFadeOut( typingFrame, 0.6, typingFrame:GetAlpha(), 0 )
			C_Timer.After( 0.6, function()
				if #Me.WhoIsTyping == 0 then
					typingFrame:Hide()
				end
			end )
		end
	end
end

-------------------------------------------------------------------------------
-- Add/remove a name from the typing list.
--
local function SetTyping( name, typing )
	for i = #Me.WhoIsTyping, 1, -1 do
		if Me.WhoIsTyping[i] == name then
			table.remove( Me.WhoIsTyping, i )
		end
	end
	if typing then
		table.insert( Me.WhoIsTyping, name )
	end
	RefreshToast()
end

-------------------------------------------------------------------------------
-- A chat edit box changed: decide whether we're "typing" and broadcast changes.
--
local function OnEditUpdate( editBox )
	if not Me.db or not Me.db.typingEnabled then return end
	if not Me.GroupChannel() then return end  -- not in a (home) group; nothing to tell

	-- Manual flag overrides the auto-detection.
	if typingButton and typingButton.manual then
		if not selfTyping then
			selfTyping = true
			SendTypingUpdate( true )
		end
		return
	end

	local chatType = editBox:GetAttribute( "chatType" )
	local msg = editBox:GetText() or ""
	local hasText = ( #msg > 0 ) and not msg:match( "^/" )  -- ignore slash commands

	local typing = hasText and TRACKED_CHANNELS[chatType] and editBox:HasFocus() and true or false

	if typing ~= selfTyping then
		selfTyping = typing
		SendTypingUpdate( typing )
	end
end

-------------------------------------------------------------------------------
-- Manual toggle button click.
--
local function OnButtonClick( self )
	self.manual = not self.manual

	if self.Timer then
		self.Timer:Cancel()
		self.Timer = nil
	end

	if self.manual then
		self.icon:SetTexture( "Interface/Buttons/UI-GuildButton-PublicNote-Up" )
		-- Re-pulse the alert every few minutes so you don't forget it's on.
		self.Timer = C_Timer.NewTicker( 300, function()
			if self:IsShown() then
				self.alert:Show()
			end
		end )
		selfTyping = true
		SendTypingUpdate( true )
	else
		self.icon:SetTexture( "Interface/Buttons/UI-GuildButton-PublicNote-Disabled" )
		self.alert:Hide()
		selfTyping = false
		SendTypingUpdate( false )
	end

	if GameTooltip:IsOwned( self ) then
		self:GetScript( "OnEnter" )( self )
	end
	PlaySound( SOUNDKIT.IG_CHAT_EMOTE_BUTTON )
end

-------------------------------------------------------------------------------
-- Build the toast frame.
--
local function CreateToastFrame()
	local f = CreateFrame( "Frame", "EmberhollowTypingFrame", UIParent )
	f:SetSize( 301, 32 )
	f:SetFrameStrata( "LOW" )
	f:SetPoint( "BOTTOMLEFT", ChatFrame1Tab, "TOPLEFT", 0, -2 )
	f:SetAlpha( 0 )
	f:Hide()

	local bg = f:CreateTexture( nil, "BACKGROUND" )
	bg:SetAtlas( "quickjoin-toast-background" )
	bg:SetAllPoints( f )
	f.Background = bg

	local msg = f:CreateFontString( nil, "ARTWORK", "GameFontNormalSmall2" )
	msg:SetJustifyH( "LEFT" )
	msg:SetSize( 272, 11 )
	msg:SetPoint( "LEFT", f, "LEFT", 10, 2 )
	msg:SetTextColor( 0.8, 0.8, 0.8 )
	f.Message = msg

	-- Grow the frame to fit longer "Several people are typing..." text.
	f:SetScript( "OnUpdate", function( self )
		local width = self.Message:GetStringWidth() + 25
		if width < 200 then width = 200 end
		self:SetWidth( width )
	end )

	typingFrame = f
end

-------------------------------------------------------------------------------
-- Anchor the toggle button at its default spot, under the first chat tab.
--
local function AnchorButtonDefault()
	typingButton:ClearAllPoints()
	typingButton:SetPoint( "TOP", ChatFrame1Tab, "BOTTOM", 0, -4 )
end

-------------------------------------------------------------------------------
-- Apply the position saved in Me.db (relative to UIParent), or fall back to the
-- default anchor when the player has never dragged the button.
--
local function RestoreButtonPosition()
	if not typingButton then return end
	local pos = Me.db and Me.db.typingButtonPos
	if pos then
		typingButton:ClearAllPoints()
		typingButton:SetPoint( pos.point or "TOP", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0 )
	else
		AnchorButtonDefault()
	end
end

-------------------------------------------------------------------------------
-- Build the manual-toggle chat button.
--
local function CreateToggleButton()
	local b = CreateFrame( "Button", "EmberhollowTypingButton", UIParent )
	b:SetSize( 27, 26 )
	b:SetFrameStrata( "LOW" )
	b:SetPoint( "TOP", ChatFrame1Tab, "BOTTOM", 0, -4 )

	-- Build the button's state textures explicitly via SetAtlas (valid on every
	-- Texture object) rather than the Set*Atlas button shortcuts, which aren't
	-- present on Button in every client build.
	local normal = b:CreateTexture( nil, "BACKGROUND" )
	normal:SetAtlas( "chatframe-button-up", true )
	normal:SetAllPoints( b )
	b:SetNormalTexture( normal )

	local pushed = b:CreateTexture( nil, "BACKGROUND" )
	pushed:SetAtlas( "chatframe-button-down", true )
	pushed:SetAllPoints( b )
	b:SetPushedTexture( pushed )

	local highlight = b:CreateTexture( nil, "HIGHLIGHT" )
	highlight:SetAtlas( "chatframe-button-highlight", true )
	highlight:SetAllPoints( b )
	highlight:SetBlendMode( "ADD" )
	b:SetHighlightTexture( highlight )

	local icon = b:CreateTexture( nil, "OVERLAY" )
	icon:SetTexture( "Interface/Buttons/UI-GuildButton-PublicNote-Disabled" )
	icon:SetSize( 16, 16 )
	icon:SetPoint( "CENTER" )
	b.icon = icon

	local alert = b:CreateTexture( nil, "OVERLAY" )
	alert:SetAtlas( "chatframe-button-highlightalert", true )
	alert:SetPoint( "CENTER" )
	alert:SetBlendMode( "ADD" )
	alert:Hide()
	b.alert = alert

	b.manual = false

	-- Draggable + remembered position. SetUserPlaced is unreliable for custom
	-- addon frames, so we persist the dragged spot ourselves in Me.db and
	-- reapply it on the next login (see RestoreButtonPosition).
	b:SetClampedToScreen( true )
	b:SetMovable( true )
	b:EnableMouse( true )
	b:RegisterForDrag( "LeftButton" )
	b:SetScript( "OnDragStart", b.StartMoving )
	b:SetScript( "OnDragStop", function( self )
		self:StopMovingOrSizing()
		if Me.db then
			local point, _, relPoint, x, y = self:GetPoint()
			Me.db.typingButtonPos = { point = point, relPoint = relPoint, x = x, y = y }
		end
	end )

	b:SetScript( "OnClick", OnButtonClick )
	b:SetScript( "OnEnter", function( self )
		GameTooltip:SetOwner( self, "ANCHOR_RIGHT" )
		GameTooltip:ClearLines()
		if self.manual then
			GameTooltip:AddLine( "Status: |cFFFF0000Typing|r", 1, 1, 1, true )
			GameTooltip:AddLine( "You've flagged that you're writing a post to your group.", 1, 0.81, 0, true )
		else
			GameTooltip:AddLine( "Status: |cFF00FF00Not Typing|r", 1, 1, 1, true )
			GameTooltip:AddLine( "Click to flag that you're writing a longer post.", 1, 0.81, 0, true )
		end
		GameTooltip:Show()
	end )
	b:SetScript( "OnLeave", function() GameTooltip:Hide() end )

	typingButton = b
	RestoreButtonPosition()
end

-------------------------------------------------------------------------------
-- Addon-comm handler: someone else's typing state changed. (Called from Core.)
--
function Me.Typing_OnTyping( sender, typing )
	if not Me.db.typingEnabled then return end
	SetTyping( sender, typing )
end

-------------------------------------------------------------------------------
-- Show or hide the manual toggle button per the current setting.
--
function Me.Typing_RefreshButton()
	if not typingButton then return end
	if Me.db.typingEnabled then
		typingButton:Show()
	else
		typingButton:Hide()
		-- Make sure we don't leave the group thinking we're still typing.
		if selfTyping then
			selfTyping = false
			SendTypingUpdate( false )
		end
	end
end

-------------------------------------------------------------------------------
-- Failsafe: snap the manual toggle button back to its default spot under the
-- chat tab, in case it got dragged somewhere it can't be found. Visibility
-- still follows the typing setting.
--
function Me.Typing_ResetButton()
	if not typingButton then return end
	-- Forget any dragged position so it doesn't get reapplied on next login.
	if Me.db then Me.db.typingButtonPos = nil end
	AnchorButtonDefault()
	-- Failsafe reveal: undo a stray drag *and* an accidental hide / zeroed alpha
	-- (e.g. from fiddling in Edit Mode), regardless of the typing toggle.
	typingButton:SetAlpha( 1 )
	typingButton:Show()
	Me.Print( "Typing button reset and revealed at its default position." )
end

-------------------------------------------------------------------------------
function Me.Typing_Init()
	CreateToastFrame()
	CreateToggleButton()

	-- Hook every chat edit box so we notice typing in any chat window.
	-- The handler is wrapped in pcall so that, no matter what, a bug in the
	-- typing code can never break the player's ability to type/send chat.
	local function SafeEditUpdate( editBox )
		pcall( OnEditUpdate, editBox )
	end
	for i = 1, NUM_CHAT_WINDOWS do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox then
			editBox:HookScript( "OnTextChanged", SafeEditUpdate )
			editBox:HookScript( "OnEditFocusLost", SafeEditUpdate )
		end
	end

	-- Prune people who leave the group while flagged as typing.
	local f = CreateFrame( "Frame" )
	f:RegisterEvent( "GROUP_ROSTER_UPDATE" )
	f:SetScript( "OnEvent", function()
		for i = #Me.WhoIsTyping, 1, -1 do
			local name = Me.WhoIsTyping[i]
			if not UnitInParty( name ) and not UnitInRaid( name ) then
				table.remove( Me.WhoIsTyping, i )
			end
		end
		RefreshToast()
	end )

	Me.Typing_RefreshButton()
end
