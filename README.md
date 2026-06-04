# Emberhollow Pact Helper

A small, self-contained World of Warcraft addon that provides two roleplay
features extracted from [DiceMaster](../DiceMaster):

1. **Rich dice rolling** — turns the plain `Name rolls 14 (1-20)` system line into
   formatted results that understand chained dice and modifiers, with crit
   colouring, e.g. `You roll 4 and 6 = 10 (2D6)` or
   `You roll 3, 5, 2 (3D6) + 8, 1, 12 (3D12) + 6 = 37`. A single 2d12 is treated
   as Daggerheart "Duality dice": matching faces colour the total green (crit),
   otherwise the higher die makes it orange (Hope) or purple (Fear). Toggleable
   with `/eph duality`.
2. **"Typing..." indicator** — shows your group a small toast while you compose
   an in-character message, plus a chat button to flag longer posts manually.

Unlike DiceMaster it ships with **no external libraries** — everything uses the
stock WoW API.

## Commands

| Command | Effect |
| --- | --- |
| `/dice XdY+/-Z` | Roll dice, e.g. `/dice 2d6+1`, `/dice d20`, `/dice 4d4-2`. Terms chain: `/dice 2d6+1d6+3d12+6` (max 10 dice; bare numbers don't count). |
| `/dice atk` / `/dice def` | Roll `2d12` plus your stored ATK / DEF, e.g. `2d12+3`. |
| `/eph atk N` / `/eph def N` | Set your ATK / DEF modifier (with no number, shows the current value). |
| `/eph` | Show help. |
| `/eph options` | Open the options panel (also `config`, `opt`); also under Game Menu > Options > AddOns. |
| `/eph typing [on\|off]` | Toggle the typing indicator (default on). |
| `/eph resetbutton` | Failsafe: move the manual typing button back to its default spot under the chat tab and reveal it (also `resettyping`). |
| `/eph grouprolls [on\|off]` | Also show plain-text rolls broadcast by the group (default off). |
| `/eph duality [on\|off]` | Colour a single 2d12 total by Daggerheart Duality: crit (green), Hope (orange), Fear (purple). Default on; recolour the three from the options panel. |

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

## File layout

| File | Responsibility |
| --- | --- |
| `Core.lua` | Namespace, saved variables, addon-comm send/receive routing, shared helpers. |
| `Dice.lua` | Roll command, roll/result matching, chat filters, `RandomRoll` hook. |
| `Typing.lua` | Typing detection, the toast frame and the manual toggle button. |
| `Options.lua` | The Options > AddOns settings page: feature toggles and Duality colour pickers. |
| `Console.lua` | Slash command registration. |

## Note: running alongside DiceMaster

DiceMaster implements the same two features. If both addons are enabled at once
they will *both* hook `RandomRoll` and filter system roll messages, so you'll see
**duplicated** formatted rolls and typing toasts. Disable DiceMaster (or at least
don't rely on both) when using Emberhollow Pact Helper for these features.

The two addons use different addon-message prefixes (`EPH1` vs `DCM4`), so they
do not talk to each other across the network — only players who both run
Emberhollow Pact Helper will share its rich rolls and typing status.
