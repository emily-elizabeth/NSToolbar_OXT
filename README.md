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
| `toolbarSetItemEnabled` | `pItemId, pEnabled` | Enable or disable a toolbar item |
| `toolbarItemIsEnabled` | `pItemId` | Returns true if the item is enabled *(function)* |
| `toolbarSetCustomizable` | `pCustomizable` | Enable or disable user toolbar customization |
| `toolbarSetVisible` | `pVisible` | Show or hide the toolbar |
| `toolbarIsVisible` | — | Returns true if the toolbar is visible *(function)* |
| `toolbarDestroy` | — | Destroy the toolbar and release all resources |

**`pDisplayMode`** values: `"iconAndLabel"` · `"iconOnly"` · `"labelOnly"` · `"default"`

**`pIconName`** — SF Symbol name (macOS 11+), e.g. `"doc.badge.plus"`, `"folder"`, `"square.and.arrow.down"`. Falls back to `[NSImage imageNamed:]` on older systems.

**Getter functions** are called with `()` in LiveCode script:
```livecodeserver
if toolbarIsVisible() then toolbarSetVisible false
if not toolbarItemIsEnabled("saveDoc") then toolbarSetItemEnabled "saveDoc", true
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

---

## Known Issues

**Window shifts down on reopen** — When a stack is closed and reopened with the toolbar visible, the window position shifts downward. Calling `toolbarDestroy` before closing does not prevent this. The workaround is to hide the toolbar before closing the stack:

```livecodeserver
on closeStack
   toolbarSetVisible false
   toolbarDestroy
end closeStack
```

---

## Notes

- Only one toolbar per library instance is managed. To attach toolbars to multiple windows, use separate library instances.
- `toolbarReloadItems` must be called after all `toolbarAddItem` calls to populate the toolbar on creation. Items added later via `toolbarAddItem` appear immediately without needing a reload.
- `toolbarItemClicked pItemId` is sent to the script object that called `toolbarCreate`.
