# Changelog

ProseccoAdditions for WoW Forever. Newest version first.

## 0.7.0-alpha3

- The old internal names are gone. The command is /prosecco (or
  /proseccoadditions); /pui no longer works. Settings are saved as
  ProseccoAdditionsDB and are moved over from ProseccoUIDB automatically at
  the first login. Panels are named ProseccoAdditionsPanel<id>: panels
  anchored to another panel follow, but a frame of another addon anchored to
  an old ProseccoUIPanel name must be set again. Exports start with PA1;
  older PUI1 exports still import. The menu entry is Prosecco Additions.

## 0.7.0-alpha2

- At login the addon checks that EllesmereUI has every function the modules
  use. If an EllesmereUI update has removed or renamed one, no module starts
  and the chat names what is missing, instead of Lua errors.

## 0.7.0-alpha1

First alpha release.

Known issue: with EllesmereUI's Minimap in Blizzard Style, the Minimap
module treats the map as round.
