# Emberhollow Pact Helper

A small, self-contained World of Warcraft addon that provides two roleplay
features extracted from [DiceMaster](../DiceMaster):

1. **Rich dice rolling** — turns the plain `Name rolls 14 (1-20)` system line into
   formatted results that understand multiple dice and modifiers, with crit
   colouring, e.g. `You roll 4 and 6 = 10 (2D6)`. A 2d12 whose two dice match
   has its total coloured green (Daggerheart-style doubles), toggleable with
   `/eph matchcrit`.
2. **"Typing..." indicator** — shows your group a small toast while you compose
   an in-character message, plus a chat button to flag longer posts manually.

Unlike DiceMaster it ships with **no external libraries** — everything uses the
stock WoW API.

## Commands

| Command | Effect |
| --- | --- |
| `/dice XdY+/-Z` | Roll dice, e.g. `/dice 2d6+1`, `/dice d20`, `/dice 4d4-2`. |
| `/dice atk` / `/dice def` | Roll `2d12` plus your stored ATK / DEF, e.g. `2d12+3`. |
| `/eph atk N` / `/eph def N` | Set your ATK / DEF modifier (with no number, shows the current value). |
| `/eph` | Show help. |
| `/eph typing [on\|off]` | Toggle the typing indicator (default on). |
| `/eph grouprolls [on\|off]` | Also show plain-text rolls broadcast by the group (default off). |
| `/eph matchcrit [on\|off]` | Colour the total green when a 2d12 rolls two matching dice (default on). |

The native `/roll` command is hooked too, so ordinary rolls get the same rich
formatting and are shared with other addon users in your party/raid.

## How rolling works

WoW's `/roll` only ever produces a single `Name rolls X (a-b)` line. To present
multi-dice rolls with modifiers, the addon:

1. Broadcasts an addon message describing the intended roll (count/sides/mod) to
   the group via the `EPH1` prefix.
2. Calls `RandomRoll()` once per die to get real server-side random numbers.
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
| `Console.lua` | Slash command registration. |

## Note: running alongside DiceMaster

DiceMaster implements the same two features. If both addons are enabled at once
they will *both* hook `RandomRoll` and filter system roll messages, so you'll see
**duplicated** formatted rolls and typing toasts. Disable DiceMaster (or at least
don't rely on both) when using Emberhollow Pact Helper for these features.

The two addons use different addon-message prefixes (`EPH1` vs `DCM4`), so they
do not talk to each other across the network — only players who both run
Emberhollow Pact Helper will share its rich rolls and typing status.
