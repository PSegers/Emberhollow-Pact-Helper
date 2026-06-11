# Emberhollow Pact Helper

A small, self-contained World of Warcraft addon with a handful of roleplay
features. The dice rolling and "typing..." indicator were extracted from
[DiceMaster](../DiceMaster); the rest are original to this addon.

1. **Rich dice rolling** — turns the plain `Name rolls 14 (1-20)` system line into
   formatted results that understand chained dice and modifiers, with crit
   colouring, e.g. `You roll 4 and 6 = 10 (2D6)` or
   `You roll 3, 5, 2 (3D6) + 8, 1, 12 (3D12) + 6 = 37`. A single 2d12 is treated
   as Daggerheart "Duality dice": matching faces colour the total green (crit),
   otherwise the higher die makes it orange (Hope) or purple (Fear). Toggleable
   with `/eph duality`.
2. **"Typing..." indicator** — shows your group a small toast while you compose
   an in-character message, plus a chat button to flag longer posts manually.
   Both the toast bar and the button are repositioned through WoW's built-in
   Edit Mode.
3. **Marker naming** — give the eight raid target icons (Star … Skull) custom
   roleplay names, e.g. Skull = "The Cursed Altar", edited in a resizable panel
   (`/eph marker`). Names sync to your group over the addon channel. Editing is
   gated behind **DM mode**: only a DM can change or clear the names; everyone
   else sees them read-only and still receives the DM's updates.
4. **Cheat sheet** — a movable, pageable reference window for the group's dice
   rules (`/eph cheatsheet`).
5. **Dice games** — a suite of dice games (`/eph dicegames`), starting with
   **Farkle**: roll six dice, set aside the scorers, then push your luck or pass.
   The games roll their own *weighted* dice (not WoW's `/roll`) from an editable
   library, you stock a six-die pool in an inventory, and every roll/pass/bust is
   announced as an `/emote` so a group can play along.
6. **Launcher button** — a minimap button (and a matching Blizzard
   addon-compartment entry) that opens the addon's windows, plus an optional
   button on the [Total RP 3](../totalRP3) toolbar when that addon is present.

Dependencies are kept to a minimum and everything else uses the stock WoW API.
Embedded libraries (under [`Libs/`](Libs)): LibStub; EditModeExpanded-1.0 (native
Edit Mode integration for the typing UI); and LibDataBroker-1.1 + LibDBIcon-1.0
(plus CallbackHandler-1.0) for the minimap button.

## Commands

| Command | Effect |
| --- | --- |
| `/dice XdY+/-Z` | Roll dice, e.g. `/dice 2d6+1`, `/dice d20`, `/dice 4d4-2`. Terms chain: `/dice 2d6+1d6+3d12+6` (max 10 dice; bare numbers don't count). |
| `/dice atk` / `/dice def` | Roll `2d12` plus your stored ATK / DEF, e.g. `2d12+3`. |
| `/eph atk N` / `/eph def N` | Set your ATK / DEF modifier (with no number, shows the current value). |
| `/eph` | Show help. |
| `/eph options` | Open the options panel (also `config`, `opt`); also under Game Menu > Options > AddOns. |
| `/eph typing [on\|off]` | Toggle the typing indicator (default on). |
| `/eph grouprolls [on\|off]` | Also show plain-text rolls broadcast by the group (default off). |
| `/eph duality [on\|off]` | Colour a single 2d12 total by Daggerheart Duality: crit (green), Hope (orange), Fear (purple). Default on; recolour the three from the options panel. |
| `/eph marker` | Open the marker-names panel (also `mark`). As a DM you can also `/eph marker skull <name>` to set a name and `/eph marker list` to print them. |
| `/eph dm [on\|off]` | Toggle **DM mode** — only a DM may edit/clear the marker names (default off). Also in the options panel. |
| `/eph minimap [on\|off]` | Show or hide the minimap launcher button. |
| `/eph cheatsheet` | Open the reference cheat sheet window (also `cheat`, `cs`). |
| `/eph dicegames` | Open the dice games menu (also `games`). |
| `/eph farkle` | Open Farkle directly. |

The native `/roll` command is hooked too, so ordinary rolls get the same rich
formatting and are shared with other addon users in your party/raid.

## How rolling works

WoW's `/roll` only ever produces a single `Name rolls X (a-b)` line. To present
chained, multi-dice rolls with modifiers, the addon:

1. Broadcasts an addon message describing the intended roll to the group via the
   `EPH1` prefix — a single die type sends count/sides/mod, while a compound roll
   (more than one die type, e.g. `2d6+3d12`) sends its merged dice groups plus the
   combined modifier.
2. Calls `RandomRoll()` once per die, in order, to get real server-side random
   numbers.
3. Hides the raw system lines and matches them back to the announced intent,
   then prints one formatted result.

Group members without the addon still see the raw rolls plus an optional
`<Emberhollow>` summary, so nothing is lost on them.

## Marker naming & DM mode

Open the panel with `/eph marker`. It lists the eight raid target icons, each with
an editable name; the window is movable and resizable, and remembers its size and
position. Names sync to other addon users in your home party/raid over the `EPH1`
prefix (last writer wins) and persist between sessions.

Editing is reserved for a **DM**. Enable it with `/eph dm on` (or the checkbox in
the options panel); it is **off by default**. As a DM the name boxes become
editable and a **Clear All** button appears (with an "are you sure?" confirmation
before it wipes every name for you and the group). Without DM mode the names are
read-only — you can still see them and you keep receiving the DM's updates, but you
can't change them.

## Dice games

Open the games menu with `/eph dicegames` (or `/eph games`). It's built as a hub
so more games can be added over time; the first is **Farkle**.

**Farkle** (`/eph farkle`) is a solo push-your-luck game with six dice. Roll, set
aside any scoring dice, then either roll the rest for more or pass to bank the
turn. Bust (a roll with no scoring dice) and you lose everything banked that turn;
set all six aside and you get "hot dice" — roll all six again, the turn continuing.
Scoring (also on the in-window **?** sheet): each 1 = 100, each 5 = 50, three of a
kind = 100 × the face (three 1s = 1000), each extra die past the third doubles it,
and straights score 500 (1-5), 750 (2-6) or 1500 (1-6). Every roll, pass and bust
is posted as an `/emote`, so a group can follow along and keep their own scores.

The games **don't** use WoW's `/roll` — they roll their own *weighted* dice, so a
die can be loaded for or against any face. The catalogue lives in
[`DiceData.lua`](DiceData.lua) as a plain, editable list (id, name, six face
weights, description); rename dice, change the odds or add your own. In the
**inventory** (the Farkle menu's *Inventory* button) you set how many of each die
you own (0-6) and fill a six-die **pool** — duplicates allowed, up to as many as
you own — which the next game rolls with. Hover any die, in the inventory or in
the game, to see its per-face odds and flavour text.

## Launcher button

A button on the minimap (provided by LibDBIcon) opens the addon's windows; drag it
around the ring to reposition it, and toggle it with `/eph minimap`. A matching
entry is added to Blizzard's addon compartment. The clicks are:

| Click | Opens |
| --- | --- |
| Left | Options |
| Right | Marker names |
| Shift + right | Cheat sheet |

If [Total RP 3](../totalRP3) is installed, the same actions are also available from
a button added to its toolbar.

## Window styling

The cheat sheet and marker windows share a Total RP-inspired look: a parchment
texture under a soft dark overlay inside the ornate gold dialog border, with white
text for contrast. All from stock WoW textures — no bundled art.

## File layout

| File | Responsibility |
| --- | --- |
| `Core.lua` | Namespace, saved variables, addon-comm send/receive routing, shared helpers (incl. the shared window styling and launcher click handler). |
| `Dice.lua` | Roll command, roll/result matching, chat filters, `RandomRoll` hook. |
| `Typing.lua` | Typing detection, the toast frame and the manual toggle button, and their Edit Mode registration. |
| `Marker.lua` | The marker-naming panel, DM-mode gating, the Clear All button, and the `M` sync message handler. |
| `CheatSheet.lua` / `CheatSheet.xml` | The pageable reference window (behaviour / layout). |
| `DiceGames.lua` | Dice games hub: the game registry, custom weighted-dice RNG, ownership/pool helpers, the shared window builder and the die tooltip. |
| `DiceData.lua` | The editable dice library (names, weights, descriptions) as a plain Lua table. |
| `DiceInventory.lua` | The inventory window: owned counts (0-6) per die and the six-die Farkle pool. |
| `Farkle.lua` | The Farkle game: rules, scoring, the play window and the scoring-sheet reference. |
| `Minimap.lua` | The LibDBIcon minimap button and the addon-compartment entry. |
| `TRP.lua` | Optional Total RP 3 toolbar button (does nothing if TRP isn't loaded). |
| `Options.lua` | The Options > AddOns settings page: feature toggles, DM mode, and Duality colour pickers. |
| `Console.lua` | Slash command registration. |
| `Libs/` | Embedded libraries: LibStub, EditModeExpanded-1.0 (Edit Mode integration for the typing UI), and LibDataBroker-1.1 + LibDBIcon-1.0 + CallbackHandler-1.0 (minimap button). |

## Moving the typing UI

The "is typing..." bar and the manual toggle button are registered as native
**Edit Mode** elements (via EditModeExpanded). Open Edit Mode (Game Menu > Edit
Mode), where both appear as selectable, draggable frames — the bar shows a sample
"Someone is typing..." so you can place it even when nobody is. Positions are saved
per Edit Mode layout (account-wide for the default layout) and restored on login;
each frame also gets a per-frame **Reset** button in Edit Mode.

## Note: running alongside DiceMaster

DiceMaster implements the same two features. If both addons are enabled at once
they will *both* hook `RandomRoll` and filter system roll messages, so you'll see
**duplicated** formatted rolls and typing toasts. Disable DiceMaster (or at least
don't rely on both) when using Emberhollow Pact Helper for these features.

The two addons use different addon-message prefixes (`EPH1` vs `DCM4`), so they
do not talk to each other across the network — only players who both run
Emberhollow Pact Helper will share its rich rolls and typing status.
