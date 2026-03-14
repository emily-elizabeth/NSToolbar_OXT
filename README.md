# org.openxtalk.nstoolbar

A native macOS NSToolbar library for OpenXTalk and LiveCode, built using LiveCode Builder (LCB) with an Objective-C glue dylib. Supports multiple simultaneous toolbars, each identified by a string identifier. Toolbar item clicks are delivered as `toolbarItemClicked pToolbarId, pItemId` to the script object that called `toolbarCreate`.

---

## Requirements

- **OpenXTalk 1.14** or **LiveCode 9.6** or greater
- **macOS 10.14+** (macOS 11+ recommended for SF Symbols)
- Xcode command line tools (to build the glue dylib)

---

## File Overview

```
org.openxtalk.nstoolbar/
├── org.openxtalk.nstoolbar.lcb     ← LCB library (public API)
├── LCNSToolbarDelegate.h           ← ObjC glue header
├── LCNSToolbarDelegate.m           ← ObjC glue implementation
├── build_glue.sh                   ← Script to build the universal dylib
├── api.lcdoc                       ← API documentation
└── README.md                       ← This file
```

---

## Architecture

```
LiveCode / OpenXTalk Script
        │  public handler calls (pToolbarId, ...)
        ▼
org.openxtalk.nstoolbar.lcb   (LCB library)
        │  c: foreign handler bindings
        ▼
nstoolbar_glue.dylib           (Objective-C glue)
        │  per-toolbar LCToolbarContext + NSToolbarDelegate
        ▼
NSToolbar / NSToolbarItem      (Cocoa)
        │  ToolbarClickCallback(toolbarId, itemId)
        ▼
LCB click handler → post "toolbarItemClicked" pToolbarId pItemId to caller
```

Each toolbar is tracked by its identifier string in a global context registry (`LCToolbarContext`). The NSToolbarDelegate implementation is entirely in ObjC because its callbacks return `ObjcId`, which LCB's ffi layer cannot handle safely. A single global C callback receives both the toolbar identifier and item identifier, and LCB dispatches to the correct stored target ScriptObject.

---

## Building the Glue Dylib

Run from the directory containing `LCNSToolbarDelegate.m`:

```bash
./build_glue.sh /path/to/org.openxtalk.nstoolbar
```

This produces a universal (arm64 + x86_64) dylib and installs it into:
```
org.openxtalk.nstoolbar/code/arm64-mac/nstoolbar_glue.dylib
org.openxtalk.nstoolbar/code/x86_64-mac/nstoolbar_glue.dylib
```

---

## Public API

All handlers take a `pToolbarId` as their first parameter to identify which toolbar to operate on.

| Handler | Parameters | Description |
|---|---|---|
| `toolbarCreate` | `pToolbarId, pWindowID, pDisplayMode` | Create and attach a toolbar to a stack window |
| `toolbarAddItem` | `pToolbarId, pItemId, pLabel, pIconName, pTooltip` | Add a toolbar item |
| `toolbarRemoveItem` | `pToolbarId, pItemId` | Remove a toolbar item by identifier |
| `toolbarReloadItems` | `pToolbarId` | Reload all items from the delegate |
| `toolbarSetItemLabel` | `pToolbarId, pItemId, pLabel` | Change the label of an existing item |
| `toolbarSetItemTooltip` | `pToolbarId, pItemId, pTooltip` | Change the tooltip of an existing item |
| `toolbarSetItemEnabled` | `pToolbarId, pItemId, pEnabled` | Enable or disable a toolbar item |
| `toolbarSetItemImage` | `pToolbarId, pItemId, pImagePath` | Set a custom image from a file path |
| `toolbarItemIsEnabled` | `pToolbarId, pItemId` | Returns true if the item is enabled *(function)* |
| `toolbarSetDisplayMode` | `pToolbarId, pDisplayMode` | Change the toolbar display mode at runtime |
| `toolbarSetCustomizable` | `pToolbarId, pCustomizable` | Enable or disable user customization |
| `toolbarSetVisible` | `pToolbarId, pVisible` | Show or hide the toolbar |
| `toolbarIsVisible` | `pToolbarId` | Returns true if the toolbar is visible *(function)* |
| `toolbarItems` | `pToolbarId` | Returns a newline-delimited list of item identifiers *(function)* |
| `toolbarReactivate` | `pToolbarId` | Re-registers the click callback (call from `resumeStack` if needed) |
| `toolbarDestroy` | `pToolbarId` | Destroy the toolbar and release all resources |

**`pDisplayMode`** values: `"iconAndLabel"` · `"iconOnly"` · `"labelOnly"` · `"default"`

**`pIconName`** — SF Symbol name (macOS 11+), e.g. `"doc.badge.plus"`, `"folder"`, `"square.and.arrow.down"`. Falls back to `[NSImage imageNamed:]` on older systems.

**`pLabel` and `pTooltip`** — Fully Unicode-aware. Japanese, Chinese, Arabic, emoji and other non-ASCII text are all supported.

**Getter functions** require parentheses in LiveCode script:
```livecode script
if toolbarIsVisible("MainToolbar") then toolbarSetVisible "MainToolbar", false
if not toolbarItemIsEnabled("MainToolbar", "saveDoc") then ...
put toolbarItems("MainToolbar") into tItems  -- newline-delimited
```

---

## Usage

### Single toolbar

```livecode script
on openCard
   toolbarCreate "MainToolbar", the windowID of this stack, "iconAndLabel"
   toolbarAddItem "MainToolbar", "newDoc",  "New",  "doc.badge.plus",        "New Document"
   toolbarAddItem "MainToolbar", "openDoc", "Open", "folder",                "Open Document"
   toolbarAddItem "MainToolbar", "saveDoc", "Save", "square.and.arrow.down", "Save Document"
   toolbarReloadItems "MainToolbar"
end openCard

on closeStack
   toolbarSetVisible "MainToolbar", false
   toolbarDestroy "MainToolbar"
end closeStack

on resumeStack
   toolbarReactivate "MainToolbar"
end resumeStack

on toolbarItemClicked pToolbarId, pItemId
   switch pItemId
      case "newDoc"
         -- handle New
      case "openDoc"
         -- handle Open
      case "saveDoc"
         -- handle Save
   end switch
end toolbarItemClicked
```

### Multiple toolbars

```livecode script
on openCard
   -- Main window toolbar
   toolbarCreate "MainToolbar", the windowID of stack "Main", "iconAndLabel"
   toolbarAddItem "MainToolbar", "newDoc", "New", "doc.badge.plus", "New Document"
   toolbarReloadItems "MainToolbar"

   -- Inspector window toolbar
   toolbarCreate "Inspector", the windowID of stack "Inspector", "iconOnly"
   toolbarAddItem "Inspector", "attributes", "Attributes", "slider.horizontal.3", ""
   toolbarAddItem "Inspector", "behaviours", "Behaviours", "bolt", ""
   toolbarReloadItems "Inspector"
end openCard

on toolbarItemClicked pToolbarId, pItemId
   switch pToolbarId
      case "MainToolbar"
         -- handle main toolbar clicks
      case "Inspector"
         -- handle inspector toolbar clicks
   end switch
end toolbarItemClicked
```

### Custom images from LiveCode image objects

Export the image to a temp file first, then pass the path:

```livecode script
local tFile
put specialFolderPath("temp") & "/myicon.png" into tFile
export image "myIcon" to file tFile as PNG
toolbarSetItemImage "MainToolbar", "myItem", tFile
```

---

## Migrating from v1.x

v2.0.0 is a breaking change. The key differences are:

1. **All handlers now take `pToolbarId` as their first parameter.**
2. **`toolbarCreate` parameter order changed** — `pToolbarId` is now first, before `pWindowID`.
3. **`toolbarItemClicked` now receives two parameters** — `pToolbarId, pItemId` instead of just `pItemId`.

```livecode script
-- v1.x
toolbarCreate the windowID of this stack, "MyToolbar", "iconAndLabel"
toolbarAddItem "saveDoc", "Save", "square.and.arrow.down", "Save"
on toolbarItemClicked pItemId ...

-- v2.0
toolbarCreate "MyToolbar", the windowID of this stack, "iconAndLabel"
toolbarAddItem "MyToolbar", "saveDoc", "Save", "square.and.arrow.down", "Save"
on toolbarItemClicked pToolbarId, pItemId ...
```

---

## Known Issues

**Window shifts down on reopen** — Hide the toolbar before closing as a workaround:

```livecode script
on closeStack
   toolbarSetVisible "MainToolbar", false
   toolbarDestroy "MainToolbar"
end closeStack
```

**IDE only — toolbar clicks stop firing after screen lock** — In the OpenXTalk/LiveCode IDE, `toolbarItemClicked` may stop firing after the screen is locked and unlocked. Call `toolbarReactivate` from `resumeStack` as a workaround. This does not affect standalone applications.

**NSToolbarFlexibleSpaceItem** — Flexible space items are not currently supported.

---

## Notes

- Each toolbar is independently managed by its identifier. There is no limit on the number of simultaneous toolbars.
- `toolbarReloadItems` must be called after the initial set of `toolbarAddItem` calls. Items added later appear immediately.
- `toolbarItemClicked pToolbarId, pItemId` is sent to the script object that called `toolbarCreate` for that toolbar.
- `NSToolbarSpaceItem` (fixed space) is supported as an item identifier.
