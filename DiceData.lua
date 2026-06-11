-------------------------------------------------------------------------------
-- Emberhollow Pact Helper -- Dice library (data)
-------------------------------------------------------------------------------
--
-- This is the editable list of dice the dice games can use. You only ever need
-- to touch the DICE LIBRARY block below -- rename dice, change their odds, write
-- new descriptions, or add/remove whole entries. Nothing here is "code" you
-- need to understand; it's just a list.
--
-- Each entry has four fields:
--   id       a unique tag. Keep it unique and DON'T change it once a die can be
--            owned (ownership + the dice pool are saved under this id).
--   name     shown in the inventory and on the Farkle dice rows. Rename freely.
--   weights  six relative odds for faces 1..6. They need not add up to 100 --
--            they're compared against each other (a 0 means that face never
--            comes up). { 1, 1, 1, 1, 1, 1 } is a fair die.
--   desc     the flavour line shown in the inventory hover tooltip.
--
-- After editing, save the file and type /reload in game.
--

local _, Me = ...   -- addon plumbing; ignore this one line

--=============================================================================
--   DICE LIBRARY  --  EDIT FREELY BELOW
--=============================================================================

Me.DICE_LIBRARY = {

	{ id = "devil_die_gold", name = "Alfonse's devil die",   weights = { 16.7, 16.7, 16.7, 16.7, 16.7, 16.7 }, desc = "One of Alfonse's custom-made dice, this one having a devil's head instead of a one." },
	{ id = "die_alfons",     name = "Alfonse's die",         weights = { 38.5,  7.7,  7.7,  7.7, 15.4, 23.0 }, desc = "A playing die made specially for Alfonse." },
	{ id = "die_ambroz",     name = "Ambrose's dice",        weights = { 28.6, 21.4,  7.1,  7.1, 14.3, 21.4 }, desc = "Dice that belonged to Ambrose, the Sasau tailor, and now maybe to me?" },
	{ id = "die_another",    name = "Another die",           weights = { 15.4,  7.7,  7.7,  7.7, 46.2, 15.4 }, desc = "Who knows where it came from. It looks like a normal die, but blue." },
	{ id = "die_f",          name = "Biased die",            weights = { 25.0, 33.3,  8.3,  8.3, 16.7,  8.3 }, desc = "A playing die someone tried to load to their advantage, but they didn't do a very good job." },
	{ id = "die_d",          name = "Ci die",                weights = { 13.0, 13.0, 13.0, 13.0, 13.0, 34.8 }, desc = "The second in the line of demonic playing dice." },
	{ id = "devil_die",      name = "Devil's head",          weights = { 16.7, 16.7, 16.7, 16.7, 16.7, 16.7 }, desc = "A die that feels hot to the touch. In place of a one it has a devil's head, which is not something folk like to gaze upon..." },
	{ id = "die_m",          name = "Die of misfortune",     weights = {  4.5, 22.7, 22.7, 22.7, 22.7,  4.5 }, desc = "A playing die that you'd be better off throwing as far away as possible." },
	{ id = "die_i",          name = "Even number die",       weights = {  6.7, 26.7,  6.7, 26.7,  6.7, 26.7 }, desc = "Playing die loaded in favour of even numbers." },
	{ id = "die_e",          name = "Fer die",               weights = { 13.0, 13.0, 13.0, 13.0, 13.0, 34.8 }, desc = "The third and last in line of demonic dice." },
	{ id = "die_kcd",        name = "Heavenly Kingdom die",  weights = { 36.8, 10.5, 10.5, 10.5, 10.5, 21.0 }, desc = "A miraculous playing die, sent from the Heavenly Kingdom to the kingdom of men." },
	{ id = "die_l",          name = "Henry's beta die",      weights = { 11.1, 44.4, 11.1, 11.1, 11.1, 11.1 }, desc = "A playing die that Henry secretly made to bring him luck in love, which is why he'd rather not use it to gamble with." },
	{ id = "die_h",          name = "Holy Trinity die",      weights = { 18.2, 22.7, 45.5,  4.5,  4.5,  4.5 }, desc = "A blessed playing dice consecrated to the Holy Trinity in the hope of falling on three." },
	{ id = "die_c",          name = "Lu die",                weights = { 13.0, 13.0, 13.0, 13.0, 13.0, 34.8 }, desc = "The first of the line of demonic dice." },
	{ id = "die_b",          name = "Lucky die",             weights = { 27.3,  4.5,  9.1, 13.6, 18.2, 27.3 }, desc = "When fortune smiles on you, smile back. Otherwise you'll look suspicious." },
	{ id = "die_g",          name = "Lucky playing die",     weights = { 33.3,  0.0,  5.6,  5.6, 33.3, 22.2 }, desc = "A playing die that brings luck more often than you'd expect." },
	{ id = "die_matej",      name = "Matthias' lucky dice",  weights = { 27.3,  4.6,  9.1, 13.6, 18.2, 27.3 }, desc = "Playing dice that brings Matthias luck. I heard he carved it himself. From bigger dice." },
	{ id = "die_k",          name = "Odd die",               weights = { 26.7,  6.7, 26.7,  6.7, 26.7,  6.7 }, desc = "Playing die loaded in favor of odd numbers." },
	{ id = "die_p",          name = "Shrinking playing die", weights = { 22.2, 11.1, 11.1, 11.1, 11.1, 33.3 }, desc = "One of the few properly loaded dice, loaded in favour of its holder." },
	{ id = "die_o",          name = "Strip die",             weights = { 25.0, 12.5, 12.5, 12.5, 18.8, 18.8 }, desc = "Legend has it that dice can strip more than one maiden." },
	{ id = "die_normal",     name = "The commonest die",     weights = { 16.7, 16.7, 16.7, 16.7, 16.7, 16.7 }, desc = "An exceptionally well-loaded die." },
	{ id = "test_die3",      name = "The least common die",  weights = { 66.6,  6.6,  6.6,  6.6,  6.6,  6.6 }, desc = "None." },
	{ id = "test_die",       name = "Uncommon die",          weights = { 16.7, 16.7, 16.7, 16.7, 16.7, 16.7 }, desc = "None." },
	{ id = "die_a",          name = "Unpopular die",         weights = {  9.1, 27.3, 18.2, 18.2, 18.2,  9.1 }, desc = "Sometimes the dice fall well, sometimes not. This one probably not." },

}

--=============================================================================
--   STOP  --  nothing below needs editing
--=============================================================================

-- Build the id -> die lookup the rest of the addon uses, and drop any malformed
-- entries (so a typo in the list above can't break the games).
Me.DICE_BY_ID = {}

local clean = {}
for _, d in ipairs( Me.DICE_LIBRARY ) do
	if d.id and d.name and type( d.weights ) == "table" and #d.weights >= 6 then
		clean[#clean + 1] = d
		Me.DICE_BY_ID[d.id] = d
	elseif Me.Print then
		Me.Print( "|cffff0000Skipped a malformed die entry in DiceData.lua.|r" )
	end
end
Me.DICE_LIBRARY = clean
