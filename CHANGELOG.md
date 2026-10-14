# Changelog

ProseccoAdditions (named ProseccoUI until 0.6.0-dev90) for WoW Forever.
Newest version first. Changes before 0.6.0-dev41 are recorded (in Swedish)
in the development notes, DEVNOTES.md, in the source repository.

## 0.7.0-alpha1

First alpha release.

- Microbar, Minimap, Quest Tracker and XP Bar no longer have a "To be hard
  coded" tab; its settings are fixed: volume popup 200 px wide, Blizzard's
  micro menu hidden, highlight on the icons; minimap texts outlined, its
  buttons 20 px with 2 px between; the quest tracker kept on screen, 4 px
  between quests, Quest Completed in the tracker's font, outlined; the XP
  bar's info panel opens on a click, 16 px over the bar, with times, quests
  and rested, a black 1 px line where each fill ends, rested at 38 %.

Known issue: with EllesmereUI's Minimap in Blizzard Style, the Minimap
module treats the map as round.

## 0.6.0-dev92

- The addon folder is now ProseccoAdditions. Close the game, rename the
  folder Interface\AddOns\ProseccoUI to ProseccoAdditions, and copy
  WTF\Account\<account>\SavedVariables\ProseccoUI.lua to
  ProseccoAdditions.lua in the same folder, so your settings come along.
- Frame backgrounds: the grey Pixels Circle ring is drawn from
  EllesmereUI's own ring art in the game; the addon no longer carries an
  edited copy of it.
- The unused class icons of the RXP theme are removed; the guide window
  shows RestedXP's own class icon as before.
- Trinkets and Spec Profiles are off until they have been tested in game:
  the Trinkets module is not loaded, and the Profiles page has no Spec
  Profiles rows.
- License: CC BY-NC-SA 4.0 instead of MIT. Use, change and share it with
  credit, not commercially, and changed versions under the same license.

## 0.6.0-dev91

- The addon is renamed ProseccoAdditions: its title, menu, messages and
  texts say so. Commands (/pui), profiles, settings and panel frame names
  stay as they were.
- General: a new About text.
- A new README with the requirements, the modules and the commands.

## 0.6.0-dev90

- New module Trinkets (off until you turn it on): two buttons for your
  trinkets with their cooldowns. Mouse over one out of combat for a menu
  of the trinkets you carry: left-click equips, right-click puts the
  trinket in that slot's queue or takes it out. Auto Queue equips the
  first ready trinket of the queue out of combat; a trinket you equip by
  hand that is not in the queue stays on. Internal cooldowns of procs are
  not shown: the game hides the proc from addons in combat. A trinket you
  equip from the menu stays until after your next fight, and one the game
  will not equip is skipped until /reload.
- Profiles: Spec Profiles. Pick the ProseccoUI profile and the Ellesmere
  profile your character switches to when you change to your Primary or
  Secondary spec. The page says so when Ellesmere has spec profiles of its
  own, which switch Ellesmere too.

## 0.6.0-dev89

- General: switching a module no longer reloads the UI at once. The switch
  takes effect now; Reload to apply, next to the switches, brings the menu
  up to date. Modules that change other addons still ask first.
- Quest Tracker: Quest name size, the size of the quest name under Quest
  Completed. Until you move it, it follows Completed Size as before.
- Frame backgrounds: Target background switches the empty target frame,
  and Player castbar adds an empty bar with the border and background of
  Ellesmere's Cast Bar (Resource Bars) while you cast nothing. Player
  castbar starts off.

## 0.6.0-dev88

The settings menu in a new order, after Alexander's layout of 2026-10-14.

- General: an About section and the module switches; the global border,
  background and font are on a new Global Settings tab. "Target Frame" is
  now called Frame backgrounds.
- Panels: the picked panel's settings on the Panels tab, with a Rename
  button and Copy setting from panel (size, background, border and layer;
  not the name or the place). Creating and deleting panels on a new
  Add/delete panels tab, where you choose which panel to delete.
- Chat and Panels have one settings tab less: their Advanced rows moved to
  the main tab.
- Microbar: the buttons to show are on their own tab. Housing is gone
  (WoW Forever has no housing).
- Minimap, Damage Meter, Quest Tracker, XP Bar: sections in a new order,
  some rows renamed (Header Seam is Attached, Tab Seam is Header attached).
  Quest Tracker has an RXP tab with the guide rows and the guide window.
- XP Bar: Use Global Border is for the bar's own border; off, the bar gets
  its own border style, size and colour.
- Microbar, Minimap, Quest Tracker and XP Bar have a "To be hard coded" tab
  for rows that will become fixed values later. They work as before.

## 0.6.0-dev87

Fixes from the code reviews of 2026-10-13.

- A module that cannot start because another addon is missing (Minimap
  without EllesmereUI Minimap, RXP Theme without RestedXP Guides) shows as
  "not started" in /pui status instead of "on". A module whose start failed
  gives back the settings it took in other addons when it is turned off.
- Profile import checks the pasted settings before it replaces anything: a
  value of the wrong kind, a broken panel list or a panel id used twice is
  refused and the profile stays as it was. A panel without an id, or a
  list whose next id is too low, gets a free id.
- XP Bar: no longer moves when dragged while locked. The session (its time,
  XP per hour, kills and the time this level) survives a /reload and starts
  over at a real login.
- Damage Meter: in combat only a click on a meter window starts the short
  watch for new, moved or resized windows; a float rounding difference no
  longer writes Ellesmere's Header Height again at login.
- RXP docked under the Quest Tracker: the step list's scroll bar is not moved
  in combat; a border changed in a fight places it after combat.

## 0.6.0-dev86

- XP Bar: the info panel's sentence breaks after the session time.

## 0.6.0-dev85

- XP Bar: Panel Text Size, apart from the bar's Text Size.

## 0.6.0-dev84

- XP Bar: the info panel says "XP per hour", so a wrapped line no longer
  breaks "XP/hr" in two.

## 0.6.0-dev83

- XP Bar: the info panel's body has more padding, 15 % larger text, an empty
  line before quests and rested, and a Panel Background colour with alpha; the header more padding; Bar Text
  on Mouseover.

## 0.6.0-dev82

- XP Bar: a tidier info panel: "Progress: 215 / 1,400 XP (1,185 left)" on a
  header box with Reset Session, under it one sentence with the times, time
  to level, XP per hour and kills, then quests and rested; grey words, white
  numbers. New Panel Background Alpha.

## 0.6.0-dev81

- XP Bar: the 10 % marks are 1 px black solid lines.

## 0.6.0-dev80

- XP Bar: a mark every 10 % (the border's seam), the bar's and Reset
  Session's border white on mouseover, shift-click posts your progress
  (party chat, or /say), Kills to level from the last kill, the watched
  reputation at level 60, the info panel closes after Close After seconds
  with the mouse away; "Progress:" without its box.

## 0.6.0-dev79

- XP Bar: the info panel opens and closes with a click on the bar (Info on
  Click) instead of on mouseover, and has a progress row: a Progress badge,
  current / total XP, XP left and a Reset Session badge.

## 0.6.0-dev78

- XP Bar: no text in the middle of the bar (current / total XP is on the
  info panel).

## 0.6.0-dev77

- XP Bar: the rested fill lies over the XP and quest fills; current / total
  XP and a Reset button (session time, XP per hour) on the panel's top line;
  Quests on Mouseover shows the quest fill only while hovered;
  hidden at level 60.

## 0.6.0-dev76

- General: Global Header Texture, an Ellesmere bar texture under every
  header, title and badge box in ProseccoUI.

## 0.6.0-dev75

- XP Bar: times and rates in an info panel over the bar, on mouseover or
  always; every fill has a border line where it ends; Height down to 2.

## 0.6.0-dev74

- XP Bar: with rested XP the XP takes the rested colour and the rested part
  shows faded (Rested Alpha); quests lie over rested; the Fill Border has
  its own border settings.

## 0.6.0-dev73

- XP Bar: fixes a Lua error from the Fill Border; rested XP shows over the
  quests' XP on the bar.

## 0.6.0-dev72

- XP Bar: the border lies above the fills; new Fill Border, a border round
  the XP fill.

## 0.6.0-dev71

- New module XP Bar: an XP bar with time this level and this session,
  XP per hour, time to level, and the XP of completed quests and rested XP.

## 0.6.0-dev70

- Target Frame: the Pixels Circle portrait ring is Alexander's own edit of
  Ellesmere's ring (new file: restart the game).

## 0.6.0-dev69

- Target Frame: the portrait uses Ellesmere's own rings again (shape ring
  and Outer Ring); ProseccoUI's own ring textures are removed.

## 0.6.0-dev68

- Target Frame: the own Pixels Outer Ring is a black line, a thin line in
  the Outer Ring colour and black inward, as in Alexander's picture
  (changed file: restart the game).

## 0.6.0-dev67

- Target Frame: the portrait's Pixels Outer Ring is ProseccoUI's own, a
  band in the Outer Ring colour without the dark lines (new file: restart
  the game).

## 0.6.0-dev66

- Target Frame: the Pixels Circle ring has no dark inner line, and the
  portrait background reaches under the ring, so no dark gap shows between
  them (changed file: restart the game).

## 0.6.0-dev65

- Target Frame: a round detached portrait (Circle, Pixels Circle) gets a
  shaded disc as its background, tinted with the background colour (new
  file: restart the game).

## 0.6.0-dev64

- Damage Meter: where joined windows meet the Header Seam, the two seam
  lines cross instead of the side seam cutting the header line.

## 0.6.0-dev63

- Damage Meter: Join Side by Side (on by default). Windows placed side by
  side, tops and bottoms in line, share one border with a seam where they
  meet.

## 0.6.0-dev62

- Target Frame: Alpha fades only the backgrounds; borders and the detached
  portrait stay fully shown. Use Ellesmere Colours (on by default) or own
  colours for the border, the ring and the Outer Ring. A Pixels Circle
  portrait gets ProseccoUI's own ring without the inward shadow (new file:
  restart the game, /reload is not enough).

## 0.6.0-dev61

- Target Frame: Use Health Background (on by default) or an own background
  colour and alpha, and an Alpha slider for the whole empty frame; the
  portrait's Outer Ring stays fully shown.

## 0.6.0-dev60

- Target Frame: the detached portrait's Outer Ring and Inner Shadow; the
  shape ring always has its set colour, never the class colour; every
  background is the target frame's health bar background, and the module's
  own background setting is gone.

## 0.6.0-dev59

- Target Frame: the empty frame also copies the target frame's power bar
  (background, Power Bar Seam, a detached bar's border) and portrait (the
  grey square, a detached portrait's shape and ring, the divider).

## 0.6.0-dev58

- New module Target Frame: an empty frame with the target frame's border
  where Ellesmere's target frame stands while you have no target.

## 0.6.0-dev57

- Quest Tracker: Scroll Bar Side. The quest list's scroll bar, and in
  Guide Window: Integrated the step list's scroll bar and the guide's cog,
  can sit on the tracker's left side.

## 0.6.0-dev56

- Quest Tracker: with Steps Position Left or Right, the newest step box's
  top is level with the tracker's top; its step badge stands above it.

## 0.6.0-dev55

- Quest Tracker: Steps Position for Guide Window: Integrated. The guide's
  step boxes stand under the step list as before, or beside the tracker on
  the left or right, level with its top, newest step first. A step change
  in combat may show the old order until combat ends.
- Quest Tracker: Keep On Screen. The tracker is no taller than reaches the
  bottom of the screen together with the guide's list and steps under it;
  past that, the quest list scrolls.
- Quest Tracker: the guide progress box's background no longer shows above
  its seam line with a textured border.

## 0.6.0-dev54

- Microbar on the Minimap: the bar has no background of its own; the
  Minimap's bottom panel background lies behind it, under the border.

## 0.6.0-dev53

- Minimap: the border and seams lie one strata over the panels, so the
  border shows over the Microbar's background; the badges sit 4 px from the
  border's line.

## 0.6.0-dev52

- Minimap: the border lies over the Microbar's background where the bar
  sits under the map; the clock and FPS/MS badges sit 3 px from the
  border's line.

## 0.6.0-dev51

- Minimap with the Microbar on it: the clock and FPS/MS are two badges in
  the map's bottom corners (clock left, FPS/MS right), and one border goes
  round the map and the bar with a seam line between them.
- Microbar on the Minimap: the bar's background is fully opaque.

## 0.6.0-dev50

- Microbar: right-click on the speaker turns all sound off and on.
- Microbar: Mouseover shows the whole bar only while the mouse is over it.
- Microbar: On the Minimap puts the bar under Ellesmere's minimap, as wide as
  the map, in place of the Minimap module's bottom panel; the clock, FPS and
  latency then show as a small badge on the map.
- Minimap: Text Outline for the panels' texts.
- Minimap: the panels lie over other addons' minimap pins (Questie) in the
  rectangular map's hidden strips, and sit 2 px closer to the map.
- Chat: the edit box with a textured border ends on the seam's line.

## 0.6.0-dev49

- Microbar: the buttons are 3:4 and the icons fill them (one pixel inside
  the border).
- Minimap: the map gets a border of ProseccoUI's (General page border) that
  joins the seamed panels, with a seam line at each join; works with the
  square and rectangular shapes. Set Ellesmere Values turns Ellesmere's own
  minimap border off.

## 0.6.0-dev48

- Microbar: the buttons are 2:3 (taller than wide), not 3:2.

## 0.6.0-dev47

- Microbar: the buttons are 2:3 (taller than wide) with the icon square in
  the middle; the icon border is always black, 1 px. New icons in the same
  style for Volume, Game Menu (an Esc key) and Legacy (an hourglass). New
  files: needs a full restart of the game.

## 0.6.0-dev46

- Minimap: buttons of its own for Tracking, Calendar, Mail, Instance
  Difficulty and Zoom +/-, in a column in the map's top right corner. Each
  can show always, only while the mouse is over the map, or never. Set
  Ellesmere Values now also turns off Ellesmere's own versions of these
  buttons. Ellesmere's crafting order button stays (it cannot be turned off
  from its settings). New file: needs a full restart of the game.

## 0.6.0-dev45

- Minimap rebuilt around EllesmereUI Minimap, which it now needs: a top panel
  with the zone's name (in its PvP colour) and a bottom panel with the clock,
  FPS and latency, joined to Ellesmere's map border with a Header Seam or
  standing apart with a gap. Turning the module on (or Set Ellesmere Values)
  turns off Ellesmere's own zone text, clock and FPS readout; turning it off
  puts them back. Ellesmere's minimap itself is not moved. The dev44 border,
  background and mouseover options are gone.
- Microbar: new icons for Character, Professions, Spellbook, Talents, Quest
  Log, Guild, Group Finder, Collections, Help and Shop. New options:
  Desaturate, Mouseover Highlight, Icon Border (1 px) and Icon Background.
  Blizzard's own micro menu is hidden while the Microbar is on (Hide Blizzard
  Micro Menu, on by default). New files: needs a full restart of the game.
- Chat: with a textured border the edit box's bottom line now lies on the
  header seam instead of one pixel under it.

## 0.6.0-dev44

- New module Minimap: a border and background round Blizzard's minimap, a
  top panel with the zone's name (in its PvP colour) and a bottom panel with
  the clock, FPS and latency. Each panel can join the map with a Header Seam
  or stand apart with a gap. Every Blizzard minimap element (zone text,
  tracking, mail, difficulty, calendar, clock, addon compartment, expansion
  button, coordinates, map frame art, day/night ring) can be set to show
  only on mouseover.
  Off by default; does not start while EllesmereUI Minimap is loaded. Needs
  a full restart of the game (new file).

## 0.6.0-dev43

- Microbar replaces Volume: a bar with the game's menu buttons you pick
  (Character, Spellbook, Talents, Quest Log, Guild, Group Finder,
  Collections, Game Menu and more) and the volume speaker. The icons share
  the bar's Width, so more icons make them smaller. The speaker opens the
  volume popup as before. The menu buttons do nothing in combat; the speaker
  works. Your Volume settings (on/off, place, popup width, colours) carry
  over. Needs a full restart of the game (new file).
- Chat: a Tab Height change in Ellesmere (Chat > Tabs) moves the tab panel
  when Ellesmere's menu closes; no /reload needed.

## 0.6.0-dev42

- Damage Meter: one settings page; the Advanced page is gone. Set Ellesmere
  Values also writes the bar, bar background, bar border, icon, bar text and
  header text values (shown in a list before you confirm). The header is
  always on while the module is on (Detached Header is gone); Header Seam
  stays. Top Padding is merged into Padding. Test Bars use Ellesmere's class
  icon style and bar and icon borders.
- Chat: the panels always use the global border and background colours; the
  chat's own border and colour rows are gone. The edit box takes the global
  header colour, opaque.
- RXP Theme: new Step List colour (copied from Body on first load) and Step
  Gap (default 7 px) between the step boxes. The step number badge sits 2 px
  higher. Side Padding is greyed in Integrated mode.
- Quest Tracker: Guide Header Height sets the height of the guide title bar
  (with the guide progress) in Integrated mode; 0 keeps the old height.

## 0.6.0-dev41

- `/pui status` prints one line per module (on, off, FAILED or locked), the
  ProseccoUI version, the client build, the active profile and the related
  addons that are loaded, with their versions.
- `/pui help` lists the commands. An unknown word says so and shows the list.
- The first time ProseccoUI starts on an account, a chat line says that every
  module is off and that `/pui` opens the settings. Shown once per account.
- The General page starts with a short line saying every module starts off.
- Profiles: "Start from" in New Profile has a "Prosecco (look only)" preset:
  border and colours only, every module off, nothing placed, no panels.
- MIT license (LICENSE) for ProseccoUI's code and textures; the fonts keep
  their SIL Open Font License.
- The addon list shows the Prosecco "P" icon (`## IconTexture`).
- General has Global Font and Global Outline; Quest Tracker and RXP Theme
  follow them by default. The outline list has a Shadow mode (drop shadow,
  no outline); Quest Tracker's separate Text Shadow setting is gone and is
  migrated to it.
- RXP Theme: eight background colours become three (Header, Body, Window),
  migrated from your old values. Footer Raise (4) and Header Overlap (1) are
  fixed, so the footer and header boxes are larger than the old defaults.
  Active Targets and Active Items always have a title bar and use the
  theme's border.
- Chat: Tab Height and Edit Box Background are gone. The tab panel follows
  Ellesmere's Tab Height (after /reload); the edit box takes the tab panel's
  colour, opaque.
- Panels: the move buttons move 1 px; Nudge Step is gone.
- Quest Tracker: the progress bar border is black; the highlight border
  takes the Highlight colour at half alpha.
- Border and background rows are hidden instead of greyed while Use Global
  is on.
