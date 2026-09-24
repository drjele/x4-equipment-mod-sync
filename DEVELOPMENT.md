# Development

## Checks and formatting

Use Python 3.10 or newer and Bash. Install the pinned tools in a virtual environment:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-dev.txt
export PATH="$PWD/.venv/bin:$PATH"
python3 scripts/check.py
```

Run `python3 scripts/check.py --fix` to format Python and shell and normalize text whitespace. The same checks run on pushes and pull requests. XML is checked for well-formedness; game schemas, XPath matches and gameplay require separate X4 validation.

Use UTF-8, LF, a final newline, spaces and no trailing whitespace. Indent code with four spaces and workflow YAML with two. Use descriptive names, uppercase shell variables, constant-first equality comparisons and explicit boolean checks. Ruff's E712 rule is disabled to retain explicit boolean comparisons. Keep shell free of prose comments. Keep only short, non-obvious constraints in code; put explanations here. XML continuation attributes may align with their opening attribute. Preserve XPath selectors, savegame identifiers and embedded game expressions when applying formatting.

## Installation and publishing helpers

`install.sh` and `publish.sh` both source `lib/find_x4.sh`. The library searches usual Steam roots and additional library folders. `X4_PATH`, `X_TOOLS_PATH`
and `PROTON_PATH` override discovery. Proton Experimental is preferred when found; otherwise the helper uses the last matching Proton directory it encounters.

Installation replaces the extension directory with a copy of `extension/`. Refresh it after edits; X4 enumerates real extension directories, so a symlink does not substitute for installation. Restart the game after installing or removing.

Publishing stages a separate copy inside the game's extensions directory. The repository keeps its readable extension id; `steam/workshop-id` holds the numeric Workshop id. The helper changes only the staged manifest, runs the interactive WorkshopTool and restores the manual installation after success. On Linux it runs WorkshopTool through Proton and maps paths through drive Z. A failed upload can leave the staged copy behind; rerun `./install.sh` to restore it.

## Release metadata

`content.xml` uses an integer version multiplied by 100 and an ISO release date. The date matches the corresponding released entry in `CHANGELOG.md`. Development changes belong under `Unreleased`; they do not advance the manifest's release version or date. An unreleased scaffold may retain its initial creation date until its first release. Keep existing extension ids stable.

## Implementation constraints

### extension/ui/drjele_equipment_mod_sync.lua

Loaded through `extension/ui.xml`, the same way Egosoft's own DLCs add Lua, after `ego_detailmonitor`, so `ShipConfigurationMenu` is already registered in `Menus`. No vanilla file is replaced; four functions of that menu are wrapped and the originals are called through.

- `buttonInstallMod` is what every Install and Reroll button calls. The vanilla handlers look it up on `menu` at click time, so the wrapper sees every click. With the checkbox off, or for a category with a single slot (engines, ship), it only forwards.
- With the checkbox on, it installs on the clicked slot, then walks the other slots of the same category and calls the original function for each, so each one goes through vanilla's own dismantle, payment and install path. The slot list mirrors `displayModifySlots`: shield groups, turret groups when the ship has upgrade groups, otherwise the individual weapon or turret slots with something mounted.
- Whether the click is an install or a reroll is read from the clicked slot before anything changes: a reroll is a click on a slot that already holds the same mod. A reroll batch skips empty slots; an install batch fills them.
- A slot is skipped when the mod is incompatible (the same `Check*ModCompatibility` call vanilla uses to decide which blueprints to list), or when it holds a different mod and the replace setting is off. The batch stops at the first slot it cannot pay for: `craftableamount` for a new install, `normalcraftableamount` for a reroll (the primary part comes back from the dismantle), and money at a wharf that is not the player's.
- `refreshMenu` is stubbed out for the length of the batch, so the menu is rebuilt once at the end instead of once per slot. `initialLoadoutStatistics` is kept from the first install, so the stat comparison shows the change the whole batch made.
- Bonus matching compares, after the batch, the set of properties each slot's mod changes from its base value (`Helper.modProperties`, as `displayModSlot` does to list them) against the clicked slot. A slot that differs is rerolled by calling `Dismantle*Mod` and `Install*Mod` directly, bypassing `buttonInstallMod`, so no money is charged. The materials the engine consumes are made free around each reroll: the inventory of the mod's resource wares is snapshotted, anything short of one reroll is added with `AddInventory`, and after the reroll the inventory is set back to the snapshot with `AddInventory` and `RemoveInventory`, the same globals the crafting menu uses. If the inventory cannot be set back, the matching stops so nothing more is spent.
- Every batch reads the player's credits and the mod's material wares at the start, after the paid slots and after the free rerolls, all within the one click, so nothing else in the game can move them in between. The differences go into the result line, and into one `DebugError` line per batch when `$DrJeleEquipmentModSyncDebug` is on.
- The default of 100 free rerolls per slot comes from play: with 20, a clicked slot that rolled a rare bonus combination (one without the heavily weighted cooling, say) left one or two slots unmatched in 3 batches out of 11.
- `displayModSlot` adds the checkbox row on its first call of each render; `displayModifySlots` resets that flag. The row goes into the table vanilla passes in, so nothing about the layout is rebuilt.

No lua interpreter is required by the checks. A syntax check can be run with `luaparser`, or with `luajit -bl` where LuaJIT is installed.

### Settings

All settings live on the player entity's blackboard, which Lua reads with `GetNPCBlackboard` and MD writes as `player.entity.$...`, from the SirNukes options callbacks in `extension/md/drjele_equipment_mod_sync_options.xml`. Unset means the default.

| Blackboard value                       | Default |
|----------------------------------------|---------|
| `$DrJeleEquipmentModSyncDefaultOn`     | 0       |
| `$DrJeleEquipmentModSyncReplace`       | 1       |
| `$DrJeleEquipmentModSyncMatchBonus`    | 1       |
| `$DrJeleEquipmentModSyncMatchAttempts` | 100     |
| `$DrJeleEquipmentModSyncDebug`         | 0       |

The switches are SirNukes `button` options, which render as a toggle and hand the callback a boolean; the callbacks store it as 0 or 1. The rerolls count is a slider. An option's `$id` must keep its type, range and unit once shipped; a stored value that does not fit the widget breaks the whole Extension Options menu. That is why the switches, which were 0/1 sliders during development, carry new `_toggle` ids.

The checkbox itself is not a setting: it is held in Lua for as long as the Modify screen is open, starts from `$DrJeleEquipmentModSyncDefaultOn`, and is reset by the wrapped `cleanup`.
