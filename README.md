FREE SCRIPT https://siik-scripts-store.tebex.io/package/7290135

# 🛢️ SiiK-H-Fuel-Refining

Industrial oil pumping, refining, storage, and vehicle fueling system for **QBCore (FiveM)**.

This resource replaces traditional fuel stations with a full **oil production pipeline**:
pump crude oil → refine it → store it in drums → fill jerrycans → refuel vehicles.

Built for serious RP servers.

---

## ✨ Features

- SQL-persistent **pumpjacks**, **refineries**, and **oil drums**
- Placeable industrial props (owner-only pickup)
- Third-eye interaction (qb-target / ox_target)
- Skill-based pumping, refining, pouring (qb-minigames)
- Fuel drums with live-updating UI
- **Metadata-based jerrycans (partial usage, realistic)**
- Vehicle fuel consumption by GTA vehicle class
- Full **qb-hud** fuel integration
- Placement zone restrictions (client + server enforced)
- Industrial-themed NUI

---

## 📦 Dependencies

Required:
- qb-core
- qb-inventory **v2.0.0**
- qb-target **or** ox_target
- qb-minigames
- qb-hud
- oxmysql

---

## ⚙️ Installation

### 1️⃣ Resource
Place the resource as:

--SiiK fuel refining
['crude_oil'] = { name='crude_oil', label='Crude Oil', weight=2000, type='item', image='crude_oil.png', unique=false, useable=false, shouldClose=true, description='Unrefined crude oil.' },
['refined_fuel'] = { name='refined_fuel', label='Refined Fuel', weight=1500, type='item', image='refined_fuel.png', unique=false, useable=false, shouldClose=true, description='Processed fuel ready for drums.' },

['empty_jerrycan'] = { name='empty_jerrycan', label='Empty Jerrycan', weight=1000, type='item', image='empty_jerrycan.png', unique=false, useable=false, shouldClose=true, description='Empty container for fuel.' },

-- ✅ MUST be useable true (Option B uses metadata)
['fuel_jerrycan'] = { name='fuel_jerrycan', label='Fuel Jerrycan', weight=1500, type='item', image='fuel_jerrycan.png', unique=false, useable=true, shouldClose=true, description='Use to refuel a vehicle. Stores fuel amount in metadata.' },

['oil_drum_kit'] = { name='oil_drum_kit', label='Oil Drum Kit', weight=2500, type='item', image='oil_drum_kit.png', unique=false, useable=true, shouldClose=true, description='Placeable fuel drum.' },
['refinery_kit'] = { name='refinery_kit', label='Refinery Kit', weight=6000, type='item', image='refinery_kit.png', unique=false, useable=true, shouldClose=true, description='Placeable refinery machine.' },
['pumpjack_kit'] = { name='pumpjack_kit', label='Pumpjack Kit', weight=8000, type='item', image='pumpjack_kit.png', unique=false, useable=true, shouldClose=true, description='Placeable pumpjack.' },



--qb-inventory 2.0.0 UI Edits (Tooltip + Slot Fuel Bar)
--1) Tooltip: Show “Fuel: X / Y (%)” and hide raw metadata keys

File: qb-inventory/html/js/app.js
Function: generateTooltipContent(item)

Find this block inside generateTooltipContent(item) (it loops Object.entries(item.info)):

if (item.info && Object.keys(item.info).length > 0 && item.info.display !== false) {
    for (const [key, value] of Object.entries(item.info)) {
        if (key !== "description" && key !== "display") {
            let valueStr = value;
            if (key === "attachments") {
                valueStr = Object.keys(value).length > 0 ? "true" : "false";
            }
            content += `<div class="tooltip-info"><span class="tooltip-info-key">${this.formatKey(key)}:</span> ${valueStr}</div>`;
        }
    }
}


Replace it with:

if (item.info && Object.keys(item.info).length > 0 && item.info.display !== false) {

    // ✅ SiiK: Pretty fuel display for charged jerrycans (hide raw keys)
    if (item.name === "fuel_jerrycan") {
        const fuel = Number(item.info.fuel ?? 0);
        const maxFuel = Number(item.info.maxFuel ?? 25);
        if (!isNaN(fuel) && !isNaN(maxFuel) && maxFuel > 0) {
            const pct = Math.max(0, Math.min(100, Math.round((fuel / maxFuel) * 100)));
            content += `<div class="tooltip-info">
                <span class="tooltip-info-key">Fuel:</span> ${fuel.toFixed(0)} / ${maxFuel.toFixed(0)} (${pct}%)
            </div>`;
        }
    }

    for (const [key, value] of Object.entries(item.info)) {
        // Hide these so it doesn't show "fuel: 17" and "maxFuel: 25" separately
        if (key === "fuel" || key === "maxFuel") continue;

        if (key !== "description" && key !== "display") {
            let valueStr = value;
            if (key === "attachments") {
                valueStr = Object.keys(value).length > 0 ? "true" : "false";
            }
            content += `<div class="tooltip-info"><span class="tooltip-info-key">${this.formatKey(key)}:</span> ${valueStr}</div>`;
        }
    }
}

--2) Slot Bar: Use the durability bar as a fuel bar for the jerrycan
--2A) Add 2 methods to app.js

File: qb-inventory/html/js/app.js
Inside methods: { ... } add these:

// ✅ SiiK: durability bar percent for items (fuel jerrycan uses info.fuel / info.maxFuel)
getItemBarPercent(item) {
    if (!item) return null;

    // Fuel jerrycan bar (metadata)
    if (item.name === "fuel_jerrycan" && item.info) {
        const fuel = Number(item.info.fuel ?? 0);
        const maxFuel = Number(item.info.maxFuel ?? 25);
        if (!isNaN(fuel) && !isNaN(maxFuel) && maxFuel > 0) {
            const pct = Math.round((fuel / maxFuel) * 100);
            return Math.max(0, Math.min(100, pct));
        }
    }
    return null;
},

getBarClass(percent) {
    const p = Number(percent ?? 0);
    if (p >= 66) return "high";
    if (p >= 33) return "medium";
    return "low";
},

--2B) Add the bar HTML inside each item slot

File: qb-inventory/html/index.html (or whatever your inventory HTML template is)
Find your .item-slot loop where each slot renders an item.

Add this inside each item-slot, near the bottom of the slot:

<!-- ✅ SiiK: Slot bar (shows jerrycan fuel %) -->
<div v-if="getItemBarPercent(item) !== null" class="item-slot-durability">
  <div
    class="item-slot-durability-fill"
    :class="getBarClass(getItemBarPercent(item))"
    :style="{ width: getItemBarPercent(item) + '%' }"
  ></div>
</div>


If your slot variable isn’t named item, replace it with your slot variable name.

--3) CSS (optional)

Your main.css already has the durability bar styling:
.item-slot-durability, .item-slot-durability-fill, .high/.medium/.low.

If you want the tooltip keys a bit bolder, add this to the bottom of qb-inventory/html/css/main.css:

.tooltip-info-key {
    font-weight: 700;
    margin-right: 6px;
}

✅ Jerrycan metadata required for these UI features

Your fuel script must store this metadata on fuel_jerrycan:

info = {
  fuel = 25,
  maxFuel = 25
}
