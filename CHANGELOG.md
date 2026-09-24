# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [v1.0.0] - 2026-09-24 - Initial release

### Added

- **Apply to all compatible slots in this category** checkbox on the ship Modify screen, for weapons, turrets and shields. Installing or rerolling a mod on one slot does the same on every other compatible slot of that category, each paid for through vanilla's own install path, and stops at the first slot it cannot afford.
- Install fills every compatible slot of the category, empty ones included; Reroll only touches slots that already hold a mod.
- **Bonus effect matching**: after applying to all, every slot whose randomly picked bonus effects differ from the clicked slot's is rerolled for free until they match, up to a configurable number of rerolls per slot. Only the first install or reroll of each slot is paid.
- A result line under the checkbox with what the last batch applied, skipped and matched, and the credits the paid slots and the free rerolls each cost.
- Extension Options, through SirNukes Mod Support APIs: **Checkbox ticked on open**, **Replace a different mod** (on by default; off skips the slot), **Match bonus effects**, **Free rerolls per slot** and **Debug logging**.

### Notes

- Loaded through the extension's `ui.xml`; no vanilla file is replaced and nothing is patched. Works with Protected UI Mode on and on top of kuertee's UI Extensions.
- The size of each roll stays the game's; the game offers no way to set a mod's values. Pair it with a mod that sets the equipment mod ranges to their maximum for identical values on every slot.

[v1.0.0]: https://github.com/drjele/x4-equipment-mod-sync/releases/tag/v1.0.0
