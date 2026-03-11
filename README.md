# org.openxtalk.nstoolbar

A native macOS NSToolbar library for OpenXTalk and LiveCode, built using LiveCode Builder (LCB) with an Objective-C glue dylib. Adds a fully functional macOS toolbar to any stack window, with SF Symbol icon support and click delivery via script messages.

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
├── ExampleUsage.livecodescript     ← Example card script
├── api.lcdoc                       ← API documentation
└── README.md                       ← This file
```

---

## Architecture

```
LiveCode / OpenXTalk Script
        │  public handler calls
        ▼
org.openxtalk.nstoolbar.lcb   (LCB library)
        │  c: foreign handler bindings
        ▼
nstoolbar_glue.dylib           (Objective-C glue)
        │  NSToolbarDelegate + target/action
        ▼
NSToolbar / NSToolbarItem      (Cocoa)
        │  ToolbarClickCallback (C function pointer)
        ▼
LCB click handler → post "toolbarItemClicked" to caller
```

The NSToolbarDelegate protocol is implemented entirely in the ObjC glue because its callbacks return `ObjcId`, which LCB's ffi layer cannot handle safely. All other operations (toolbar creation, window attachment, item insertion) are also routed through the glue via plain C functions to avoid `objc:` binding type mismatches. Click delivery uses a typed `foreign handler type` callback registered with the glue, dispatched on the main thread via `post`.

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

| Handler | Parameters | Description |
|---|---|---|
| `toolbarCreate` | `pWindowID, pIdentifier, pDisplayMode` | Create and attach toolbar to a stack window |
| `toolbarAddItem` | `pItemId, pLabel, pIconName, pTooltip` | Add a toolbar item |
| `toolbarRemoveItem` | `pItemId` | Remove a toolbar item by identifier |
| `toolbarReloadItems` | — | Reload all items from the delegate (call after adding items) |
| `toolbarSetItemLabel` | `pItemId, pLabel` | Change the label of an existing toolbar item |
| `toolbarSetItemTooltip` | `pItemId, pTooltip` | Change the tooltip of an existing toolbar item |
| `toolbarSetItemEnabled` | `pItemId, pEnabled` | Enable or disable a toolbar item |
| `toolbarSetItemImage` | `pItemId, pImagePath` | Set a custom image for a toolbar item from a file path |
| `toolbarItemIsEnabled` | `pItemId` | Returns true if the item is enabled *(function)* |
| `toolbarSetDisplayMode` | `pDisplayMode` | Change the toolbar display mode at runtime |
| `toolbarSetCustomizable` | `pCustomizable` | Enable or disable user toolbar customization |
| `toolbarSetVisible` | `pVisible` | Show or hide the toolbar |
| `toolbarIsVisible` | — | Returns true if the toolbar is visible *(function)* |
| `toolbarItems` | — | Returns a newline-delimited list of current item identifiers *(function)* |
| `toolbarReactivate` | — | Re-registers the click callback (call from `resumeStack` if needed) |
| `toolbarDestroy` | — | Destroy the toolbar and release all resources |

**`pDisplayMode`** values: `"iconAndLabel"` · `"iconOnly"` · `"labelOnly"` · `"default"`

**`pIconName`** — SF Symbol name (macOS 11+), e.g. `"doc.badge.plus"`, `"folder"`, `"square.and.arrow.down"`. Falls back to `[NSImage imageNamed:]` on older systems.

**`pLabel` and `pTooltip`** — Fully Unicode-aware. Japanese, Chinese, Arabic, emoji and other non-ASCII text are all supported.

**Getter functions** are called with `()` in LiveCode script:
```livecodeserver
if toolbarIsVisible() then toolbarSetVisible false
if not toolbarItemIsEnabled("saveDoc") then toolbarSetItemEnabled "saveDoc", true
put toolbarItems() into tItems -- newline-delimited list of item identifiers
```

---

## Usage

```livecodeserver
on openCard
   toolbarCreate the windowID of this stack, "MyToolbar", "iconAndLabel"
   toolbarAddItem "newDoc",   "New",   "doc.badge.plus",        "New Document"
   toolbarAddItem "openDoc",  "Open",  "folder",                "Open Document"
   toolbarAddItem "saveDoc",  "Save",  "square.and.arrow.down", "Save Document"
   toolbarReloadItems
end openCard

on closeCard
   toolbarDestroy
end closeCard

on toolbarItemClicked pItemId
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

### Custom images from LiveCode image objects

Export the image to a temp file first, then pass the path:

```livecodeserver
local tFile
put specialFolderPath("temp") & "/myicon.png" into tFile
export image "myIcon" to file tFile as PNG
toolbarSetItemImage "myItem", tFile
```

---

## Known Issues

**Window shifts down on reopen** — When a stack is closed and reopened with the toolbar visible, the window position shifts downward. Calling `toolbarDestroy` before closing does not prevent this. The workaround is to hide the toolbar before closing the stack:

```livecodeserver
on closeStack
   toolbarSetVisible false
   toolbarDestroy
end closeStack
```

**IDE only — toolbar clicks stop firing after screen lock** — In the OpenXTalk/LiveCode IDE, `toolbarItemClicked` may stop firing after the screen is locked and unlocked. Workarounds include navigating to another card or editing a script to refresh the IDE's message context. This does not affect standalone applications.

---

## Notes

- Only one toolbar per library instance is managed. To attach toolbars to multiple windows, use separate library instances.
- `toolbarReloadItems` must be called after all `toolbarAddItem` calls to populate the toolbar on creation. Items added later via `toolbarAddItem` appear immediately without needing a reload.
- `toolbarItemClicked pItemId` is sent to the script object that called `toolbarCreate`.
- `NSToolbarSpaceItem` (fixed space) is supported as an item identifier. `NSToolbarFlexibleSpaceItem` is not currently supported.
- Call `toolbarReactivate` from `resumeStack` as a precaution if click delivery issues occur after returning from screen lock in standalone apps.
