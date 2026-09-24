local ffi = require("ffi")
local C = ffi.C
ffi.cdef[[
    typedef uint64_t UniverseID;
    UniverseID GetPlayerID(void);
    bool CheckGroupedShieldModCompatibility(UniverseID defensibleid, UniverseID contextid, const char* group, const char* wareid);
    bool CheckWeaponModCompatibility(UniverseID weaponid, const char* wareid);
    void DismantleGroupedWeaponMod(UniverseID defensibleid, UniverseID contextid, const char* group);
    void DismantleShieldMod(UniverseID defensibleid, UniverseID contextid, const char* group);
    void DismantleWeaponMod(UniverseID weaponid);
    bool InstallGroupedWeaponMod(UniverseID defensibleid, UniverseID contextid, const char* group, const char* wareid);
    bool InstallShieldMod(UniverseID defensibleid, UniverseID contextid, const char* group, const char* wareid);
    bool InstallWeaponMod(UniverseID weaponid, const char* wareid);
]]

local SETTING_DEFAULT_ON = "$DrJeleEquipmentModSyncDefaultOn"
local SETTING_REPLACE = "$DrJeleEquipmentModSyncReplace"
local SETTING_MATCH_BONUS = "$DrJeleEquipmentModSyncMatchBonus"
local SETTING_MATCH_ATTEMPTS = "$DrJeleEquipmentModSyncMatchAttempts"
local SETTING_DEBUG = "$DrJeleEquipmentModSyncDebug"

local TEXT_LABEL = "Apply to all compatible slots in this category"
local TEXT_MOUSEOVER = "Installing a mod on one slot installs it on every other slot listed here that accepts it; rerolling one rerolls every other slot that already holds a mod and leaves empty slots alone. Each slot is paid for once, as if clicked by hand. It stops at the first slot you cannot afford. With bonus matching on, slots whose bonus effects differ from the clicked one are rerolled again for free until they match."
local TEXT_RESULT = "Last batch: %d applied, %d skipped"
local TEXT_STOPPED = " - stopped, out of resources or money"
local TEXT_MATCH = ". Bonus effects: %d matched, %d not matched, %d free rerolls"
local TEXT_BLOCKED = " - free rerolls stopped, the game refused to restore the materials"
local TEXT_COST = ". Paid %s Cr; free rerolls cost %s Cr"

local menu
local original = {}
local state = {
    batch = false,
    headerShown = false,
    lastResult = nil,
    sync = nil,
}

local function playerEntity()
    return ConvertStringTo64Bit(tostring(C.GetPlayerID()))
end

local function readSetting(key, default)
    local value = GetNPCBlackboard(playerEntity(), key)
    if nil == value then
        return default
    end
    return value
end

local function isSyncEnabled()
    if nil == state.sync then
        state.sync = 0 ~= readSetting(SETTING_DEFAULT_ON, 0)
    end
    return state.sync
end

local function sameId(a, b)
    return tostring(a) == tostring(b)
end

local function collectTargets(upgrademode)
    local targets = {}
    if "shield" == upgrademode then
        for _, groupdata in ipairs(menu.shieldgroups or {}) do
            table.insert(targets, { type = "shield", component = menu.object, context = groupdata.context, group = groupdata.group })
        end
    elseif ("turret" == upgrademode) and next(menu.groups or {}) then
        for _, groupdata in ipairs(menu.turretgroups or {}) do
            if 0 ~= groupdata.currentcomponent then
                table.insert(targets, { type = "turret", component = menu.object, context = groupdata.context, group = groupdata.group, isgroup = true, weapon = groupdata.currentcomponent })
            end
        end
    elseif ("weapon" == upgrademode) or ("turret" == upgrademode) then
        local upgradetype = Helper.findUpgradeType(upgrademode)
        if upgradetype and (not upgradetype.mergeslots) then
            for _, slotdata in ipairs(menu.slots[upgrademode] or {}) do
                if ("" ~= slotdata.currentmacro) and slotdata.component and (0 ~= slotdata.component) then
                    table.insert(targets, { type = upgrademode, component = slotdata.component, weapon = slotdata.component })
                end
            end
        end
    end
    return targets
end

local function isClickedTarget(target, component, context, group)
    if target.isgroup or ("shield" == target.type) then
        return sameId(target.context, context) and (target.group == group)
    end
    return sameId(target.component, component)
end

local function isCompatible(target, ware)
    if "shield" == target.type then
        return C.CheckGroupedShieldModCompatibility(menu.object, target.context, target.group, ware)
    end
    return C.CheckWeaponModCompatibility(target.weapon, ware)
end

local function installedModInfo(target)
    if "shield" == target.type then
        return Helper.getInstalledModInfo("shield", menu.object, target.context, target.group)
    elseif target.isgroup then
        return Helper.getInstalledModInfo("turret", menu.object, target.context, target.group, true)
    end
    return Helper.getInstalledModInfo(target.type, target.component)
end

local function bonusSignature(target)
    local hasmod, installedmod = installedModInfo(target)
    if not hasmod then
        return nil
    end
    local modclass = ("shield" == target.type) and "shield" or "weapon"
    local keys = {}
    for _, property in ipairs(Helper.modProperties[modclass]) do
        if installedmod[property.key] ~= property.basevalue then
            table.insert(keys, property.key)
        end
    end
    return installedmod.Ware .. ":" .. table.concat(keys, ",")
end

local function canAfford(ware, price, reroll)
    local moddata = menu.modwaresByWare and menu.modwaresByWare[ware]
    if not moddata then
        return false
    end
    local amount = reroll and moddata.normalcraftableamount or moddata.craftableamount
    if (not amount) or (amount <= 0) then
        return false
    end
    return menu.isplayerowned or (GetPlayerMoney() >= price * menu.moddingdiscounts.totalfactor)
end

local function inventoryAmounts(wares)
    local inventory = GetPlayerInventory()
    local amounts = {}
    for ware in pairs(wares) do
        amounts[ware] = inventory[ware] and inventory[ware].amount or 0
    end
    return amounts
end

local function restoreInventory(snapshot)
    local current = inventoryAmounts(snapshot)
    for ware, amount in pairs(snapshot) do
        local difference = amount - current[ware]
        if difference > 0 then
            AddInventory(nil, ware, difference)
        elseif difference < 0 then
            RemoveInventory(nil, ware, -difference)
        end
    end
    local restored = inventoryAmounts(snapshot)
    for ware, amount in pairs(snapshot) do
        if restored[ware] ~= amount then
            return false
        end
    end
    return true
end

local function rerollDirectly(target, ware)
    if target.isgroup then
        C.DismantleGroupedWeaponMod(menu.object, target.context, target.group)
        return C.InstallGroupedWeaponMod(menu.object, target.context, target.group, ware)
    elseif "shield" == target.type then
        C.DismantleShieldMod(menu.object, target.context, target.group)
        return C.InstallShieldMod(menu.object, target.context, target.group, ware)
    end
    C.DismantleWeaponMod(target.component)
    return C.InstallWeaponMod(target.component, ware)
end

local function freeReroll(target, ware)
    local moddata = menu.modwaresByWare and menu.modwaresByWare[ware]
    if not moddata then
        return false
    end
    local needed = {}
    for _, resource in ipairs(moddata.resources or {}) do
        needed[resource.ware] = resource.data.needed
    end
    local snapshot = inventoryAmounts(needed)
    for resourceware, amount in pairs(needed) do
        if snapshot[resourceware] < amount then
            AddInventory(nil, resourceware, amount - snapshot[resourceware])
        end
    end
    local available = inventoryAmounts(needed)
    for resourceware, amount in pairs(needed) do
        if available[resourceware] < amount then
            restoreInventory(snapshot)
            return false
        end
    end
    local installed = rerollDirectly(target, ware)
    local restored = restoreInventory(snapshot)
    return installed and restored
end

local function matchBonuses(targets, reference, ware)
    local limit = readSetting(SETTING_MATCH_ATTEMPTS, 100)
    local matched, unmatched, rerolls, blocked = 0, 0, 0, false
    for _, target in ipairs(targets) do
        local attempts = 0
        while (not blocked) and (attempts < limit) and (bonusSignature(target) ~= reference) do
            attempts = attempts + 1
            rerolls = rerolls + 1
            if not freeReroll(target, ware) then
                blocked = true
            end
        end
        if bonusSignature(target) == reference then
            matched = matched + 1
        else
            unmatched = unmatched + 1
        end
    end
    return matched, unmatched, rerolls, blocked
end

local function applyToOthers(type, component, ware, price, context, group, rerollclick)
    local applied, skipped, stopped = {}, 0, false
    for _, target in ipairs(collectTargets(type)) do
        if not isClickedTarget(target, component, context, group) then
            local hasmod, installedmod = installedModInfo(target)
            local reroll = hasmod and (ware == installedmod.Ware)
            if not isCompatible(target, ware) then
                skipped = skipped + 1
            elseif rerollclick and (not hasmod) then
                skipped = skipped + 1
            elseif hasmod and (not reroll) and (0 == readSetting(SETTING_REPLACE, 1)) then
                skipped = skipped + 1
            elseif not canAfford(ware, price, reroll) then
                stopped = true
                break
            else
                if target.isgroup or ("shield" == target.type) then
                    original.buttonInstallMod(target.type, menu.object, ware, price, target.context, target.group, reroll)
                else
                    original.buttonInstallMod(target.type, target.component, ware, price, nil, nil, reroll)
                end
                table.insert(applied, target)
            end
        end
    end
    return applied, skipped, stopped
end

local function clickedTarget(type, component, context, group)
    for _, target in ipairs(collectTargets(type)) do
        if isClickedTarget(target, component, context, group) then
            return target
        end
    end
    return nil
end

local function resourceWares(ware)
    local wares = {}
    local moddata = menu.modwaresByWare and menu.modwaresByWare[ware]
    for _, resource in ipairs((moddata and moddata.resources) or {}) do
        wares[resource.ware] = true
    end
    return wares
end

local function materialChange(before, after)
    local parts = {}
    for resourceware, amount in pairs(before) do
        if after[resourceware] ~= amount then
            table.insert(parts, resourceware .. " " .. (after[resourceware] - amount))
        end
    end
    return (0 < #parts) and table.concat(parts, ", ") or "none"
end

local function runBatch(type, component, ware, price, context, group, dismantle)
    local moneyStart = GetPlayerMoney()
    local materialsStart = inventoryAmounts(resourceWares(ware))
    local clicked = clickedTarget(type, component, context, group)
    local rerollclick = false
    if clicked then
        local hasmod, installedmod = installedModInfo(clicked)
        rerollclick = hasmod and (ware == installedmod.Ware)
    end

    original.buttonInstallMod(type, component, ware, price, context, group, dismantle)
    local initialLoadoutStatistics = menu.initialLoadoutStatistics
    local applied, skipped, stopped = applyToOthers(type, component, ware, price, context, group, rerollclick)
    local result = string.format(TEXT_RESULT, #applied + 1, skipped) .. (stopped and TEXT_STOPPED or "")
    local moneyPaid = GetPlayerMoney()
    local materialsPaid = inventoryAmounts(materialsStart)

    if clicked and (0 < #applied) and (0 ~= readSetting(SETTING_MATCH_BONUS, 1)) then
        local reference = bonusSignature(clicked)
        if reference then
            local matched, unmatched, rerolls, blocked = matchBonuses(applied, reference, ware)
            result = result .. string.format(TEXT_MATCH, matched, unmatched, rerolls) .. (blocked and TEXT_BLOCKED or "")
        end
    end

    local moneyFree = GetPlayerMoney()
    local materialsFree = inventoryAmounts(materialsStart)
    result = result .. string.format(TEXT_COST, ConvertMoneyString(moneyStart - moneyPaid, false, true, 0, true, false), ConvertMoneyString(moneyPaid - moneyFree, false, true, 0, true, false))
    if 0 ~= readSetting(SETTING_DEBUG, 0) then
        DebugError(string.format("drjele_equipment_mod_sync: %s | %s | paid phase: %d Cr, materials %s | free phase: %d Cr, materials %s", ware, result, moneyStart - moneyPaid, materialChange(materialsStart, materialsPaid), moneyPaid - moneyFree, materialChange(materialsPaid, materialsFree)))
    end

    menu.initialLoadoutStatistics = initialLoadoutStatistics
    return result
end

local function buttonInstallMod(type, component, ware, price, context, group, dismantle)
    if state.batch or (not isSyncEnabled()) or (0 == #collectTargets(type)) then
        return original.buttonInstallMod(type, component, ware, price, context, group, dismantle)
    end

    state.batch = true
    local refreshMenu = menu.refreshMenu
    menu.refreshMenu = function () end
    local ok, result = pcall(runBatch, type, component, ware, price, context, group, dismantle)
    menu.refreshMenu = refreshMenu
    state.batch = false

    if ok then
        state.lastResult = result
    else
        DebugError("drjele_equipment_mod_sync: " .. tostring(result))
    end
    menu.prepareModWares()
    menu.refreshMenu()
end

local function addHeaderRow(ftable, type)
    if 1 >= #collectTargets(type) then
        return
    end
    local row = ftable:addRow(true, { scaling = true })
    row[1]:createCheckBox(isSyncEnabled(), { width = Helper.standardTextHeight, height = Helper.standardTextHeight, mouseOverText = TEXT_MOUSEOVER })
    row[1].handlers.onClick = function (_, checked)
        state.sync = checked
    end
    row[2]:setColSpan(7):createText(TEXT_LABEL, { mouseOverText = TEXT_MOUSEOVER })
    if state.lastResult then
        local resultrow = ftable:addRow(false, { scaling = true })
        resultrow[2]:setColSpan(7):createText(state.lastResult, { color = Color["text_inactive"], wordwrap = true })
    end
end

local function displayModifySlots(frame)
    state.headerShown = false
    return original.displayModifySlots(frame)
end

local function displayModSlot(ftable, type, modclass, slot, slotdata, isgroup)
    if not state.headerShown then
        state.headerShown = true
        addHeaderRow(ftable, type)
    end
    return original.displayModSlot(ftable, type, modclass, slot, slotdata, isgroup)
end

local function cleanup()
    state.lastResult = nil
    state.sync = nil
    return original.cleanup()
end

local function init()
    for _, candidate in ipairs(Menus) do
        if "ShipConfigurationMenu" == candidate.name then
            menu = candidate
            break
        end
    end
    if not menu then
        DebugError("drjele_equipment_mod_sync: ShipConfigurationMenu not found")
        return
    end

    original.buttonInstallMod = menu.buttonInstallMod
    original.displayModifySlots = menu.displayModifySlots
    original.displayModSlot = menu.displayModSlot
    original.cleanup = menu.cleanup

    menu.buttonInstallMod = buttonInstallMod
    menu.displayModifySlots = displayModifySlots
    menu.displayModSlot = displayModSlot
    menu.cleanup = cleanup
end

init()
