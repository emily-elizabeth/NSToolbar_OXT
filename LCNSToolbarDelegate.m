/*
 * LCNSToolbarDelegate.m
 *
 * Implements NSToolbarDelegate in native ObjC and exports a plain C API
 * so LCB can create/destroy the delegate without touching the delegate
 * ABI directly (which caused ffi crashes when done from LCB).
 *
 * Item clicks are delivered to LiveCode via MCEngineRunOnMainThread ->
 * MCEnginePostCallback, sending "toolbarItemClicked <itemId>" to the
 * current card.
 *
 * Build (via build_glue.sh):
 *   clang -x objective-c -fobjc-arc -dynamiclib -framework Cocoa \
 *         -arch arm64  -o nstoolbar_glue_arm64.dylib  LCNSToolbarDelegate.m
 *   clang -x objective-c -fobjc-arc -dynamiclib -framework Cocoa \
 *         -arch x86_64 -o nstoolbar_glue_x86_64.dylib LCNSToolbarDelegate.m
 *   lipo -create nstoolbar_glue_arm64.dylib nstoolbar_glue_x86_64.dylib \
 *        -output nstoolbar_glue.dylib
 */

#import <Cocoa/Cocoa.h>
#import "LCNSToolbarDelegate.h"

// ---------------------------------------------------------------------------
// Click callback — set by LCB, called when a toolbar item is clicked
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Click callback — resolved at runtime via dlsym into the LCB module dylib
// ---------------------------------------------------------------------------

static char sLastClickedItem[256] = {0};

typedef void (*LCToolbarClickCallback)(const char *itemIdentifier);
static LCToolbarClickCallback sClickCallback = NULL;

void LCToolbarSetClickCallback(LCToolbarClickCallback cb) {
    sClickCallback = cb;
}

void LCToolbarClearClickCallback(void) {
    sClickCallback = NULL;
}

int LCToolbarLastClickLength(void) {
    return (int)strlen(sLastClickedItem);
}

// Protocol that LCB can implement via CreateObjcDelegate.
// All methods return void so the ffi return type is safe.
@protocol LCToolbarClickDelegate <NSObject>
- (void)toolbarItemClicked:(NSToolbarItem *)item;
@end

// ---------------------------------------------------------------------------
// Shared item registry — populated by LCToolbarItemRegister before or after
// delegate creation. The delegate reads from this at callback time.
// ---------------------------------------------------------------------------

// Maps NSString itemIdentifier -> NSDictionary {label, iconName, tooltip}
static NSMutableDictionary<NSString *, NSDictionary *> *sItemMeta(void) {
    static NSMutableDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

// Ordered array of NSString identifiers (insertion order)
static NSMutableArray<NSString *> *sItemOrder(void) {
    static NSMutableArray *a = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ a = [NSMutableArray array]; });
    return a;
}

// Maps NSString itemIdentifier -> NSImage (custom image data from LiveCode)
static NSMutableDictionary<NSString *, NSImage *> *sItemImages(void) {
    static NSMutableDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

// ---------------------------------------------------------------------------
// NSToolbarDelegate implementation
// ---------------------------------------------------------------------------

@interface LCToolbarDelegate : NSObject <NSToolbarDelegate>
@end

@implementation LCToolbarDelegate

// ---------------------------------------------------------------------------
// Click callback — invoked by NSToolbar target/action, posts notification
// that LCB's CreateObjcDelegate observer receives
// ---------------------------------------------------------------------------

- (void)toolbarItemClicked:(NSToolbarItem *)item {
    NSString *ident = item.itemIdentifier;
    if (!ident) return;
    if (sClickCallback) {
        LCToolbarClickCallback cb = sClickCallback;
        const char *itemId = [ident UTF8String];
        // Copy to heap so it's safe across the dispatch
        char *itemIdCopy = strdup(itemId);
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(itemIdCopy);
            free(itemIdCopy);
        });
    }
}

// MARK: - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [sItemOrder() copy];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    NSMutableArray *allowed = [sItemOrder() mutableCopy];
    [allowed addObject:@"NSToolbarFlexibleSpaceItem"];
    [allowed addObject:@"NSToolbarSpaceItem"];
    [allowed addObject:@"NSToolbarSeparatorItem"];
    return [allowed copy];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    // System items — return nil and let NSToolbar handle them natively.
    // Note: on some macOS versions the identifier value is privacy-redacted in
    // logs but the string comparison still works at runtime.
    BOOL isSystemItem = [itemIdentifier isEqualToString:NSToolbarSpaceItemIdentifier] ||
                        [itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier] ||
                        [itemIdentifier isEqualToString:@"NSToolbarSpaceItem"] ||
                        [itemIdentifier isEqualToString:@"NSToolbarFlexibleSpaceItem"] ||
                        [itemIdentifier hasPrefix:@"NSToolbar"] ||
                        sItemMeta()[itemIdentifier] == nil;
    if (isSystemItem) {
        return nil;
    }

    NSDictionary *meta = sItemMeta()[itemIdentifier];

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    NSString *label = meta[@"label"] ?: itemIdentifier;
    item.label        = label;
    item.paletteLabel = label;
    item.toolTip      = meta[@"tooltip"] ?: @"";

    NSString *iconName = meta[@"iconName"] ?: @"";
    NSImage *img = sItemImages()[itemIdentifier];
    if (!img && iconName.length > 0) {
        if (@available(macOS 11.0, *)) {
            img = [NSImage imageWithSystemSymbolName:iconName
                               accessibilityDescription:label];
        }
        if (!img) img = [NSImage imageNamed:iconName];
    }
    if (img) item.image = img;

    item.target = self;
    item.action = @selector(toolbarItemClicked:);
    item.autovalidates = NO;
    return item;
}

@end

// ---------------------------------------------------------------------------
// Exported C API
// ---------------------------------------------------------------------------

void LCToolbarItemRegister(const char *itemIdentifier,
                           void *label,
                           const char *iconName,
                           void *tooltip) {
    if (!itemIdentifier) return;
    NSString *ident = [NSString stringWithUTF8String:itemIdentifier];
    NSString *labelStr = label ? (__bridge NSString *)label : @"";
    NSString *tooltipStr = tooltip ? (__bridge NSString *)tooltip : @"";
    sItemMeta()[ident] = @{
        @"label":    labelStr,
        @"iconName": [NSString stringWithUTF8String:iconName ?: ""],
        @"tooltip":  tooltipStr
    };
}

void LCToolbarItemUnregister(const char *itemIdentifier) {
    if (!itemIdentifier) return;
    [sItemMeta() removeObjectForKey:[NSString stringWithUTF8String:itemIdentifier]];
}

void LCToolbarSetItemLabel(void *toolbar, const char *itemId, void *label) {
    if (!itemId || !label) return;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    NSString *labelStr = (__bridge NSString *)label;
    NSDictionary *meta = sItemMeta()[ident];
    if (!meta) return;
    sItemMeta()[ident] = @{
        @"label":    labelStr,
        @"iconName": meta[@"iconName"] ?: @"",
        @"tooltip":  meta[@"tooltip"]  ?: @""
    };
    if (toolbar) {
        NSToolbar *tb = (__bridge NSToolbar *)toolbar;
        for (NSToolbarItem *item in tb.items) {
            if ([item.itemIdentifier isEqualToString:ident]) {
                item.label = labelStr;
                item.paletteLabel = labelStr;
                break;
            }
        }
    }
}

void LCToolbarSetItemTooltip(void *toolbar, const char *itemId, void *tooltip) {
    if (!itemId || !tooltip) return;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    NSString *tooltipStr = (__bridge NSString *)tooltip;
    NSDictionary *meta = sItemMeta()[ident];
    if (!meta) return;
    sItemMeta()[ident] = @{
        @"label":    meta[@"label"]    ?: @"",
        @"iconName": meta[@"iconName"] ?: @"",
        @"tooltip":  tooltipStr
    };
    if (toolbar) {
        NSToolbar *tb = (__bridge NSToolbar *)toolbar;
        for (NSToolbarItem *item in tb.items) {
            if ([item.itemIdentifier isEqualToString:ident]) {
                item.toolTip = tooltipStr;
                break;
            }
        }
    }
}

// Returns a newline-separated list of current item identifiers.
// Caller must free the returned string.
char *LCToolbarGetItems(void *toolbar) {
    if (!toolbar) return strdup("");
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    NSMutableArray<NSString *> *idents = [NSMutableArray array];
    for (NSToolbarItem *item in tb.items) {
        [idents addObject:item.itemIdentifier];
    }
    NSString *joined = [idents componentsJoinedByString:@"\n"];
    return strdup([joined UTF8String]);
}

void LCToolbarFreeString(char *str) {
    if (str) free(str);
}

void LCToolbarItemAppendToOrder(const char *itemIdentifier) {
    if (!itemIdentifier) return;
    NSString *ident = [NSString stringWithUTF8String:itemIdentifier];
    if (![sItemOrder() containsObject:ident])
        [sItemOrder() addObject:ident];
}

void LCToolbarItemRemoveFromOrder(const char *itemIdentifier) {
    if (!itemIdentifier) return;
    [sItemOrder() removeObject:[NSString stringWithUTF8String:itemIdentifier]];
}

void LCToolbarItemsClear(void) {
    [sItemMeta() removeAllObjects];
    [sItemOrder() removeAllObjects];
    [sItemImages() removeAllObjects];
}

void LCToolbarItemSetImageFile(void *toolbar, const char *itemId,
                                const char *filePath) {
    if (!itemId || !filePath) return;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    NSString *path = [NSString stringWithUTF8String:filePath];
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
    if (!img) return;
    sItemImages()[ident] = img;
    if (toolbar) {
        NSToolbar *tb = (__bridge NSToolbar *)toolbar;
        for (NSToolbarItem *item in tb.items) {
            if ([item.itemIdentifier isEqualToString:ident]) {
                item.image = img;
                break;
            }
        }
    }
}

void LCToolbarItemSetNSImage(void *toolbar, const char *itemId, void *nsImage) {
    if (!itemId || !nsImage) return;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    NSImage *img = (__bridge NSImage *)nsImage;
    sItemImages()[ident] = img;
    // If toolbar is live, update the existing item immediately
    if (toolbar) {
        NSToolbar *tb = (__bridge NSToolbar *)toolbar;
        for (NSToolbarItem *item in tb.items) {
            if ([item.itemIdentifier isEqualToString:ident]) {
                item.image = img;
                break;
            }
        }
    }
}

void LCToolbarItemSetImageBytes(void *toolbar, const char *itemId,
                                 const unsigned char *bytes, int length) {
    if (!itemId || !bytes || length <= 0) return;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
    NSImage *img = [[NSImage alloc] initWithData:data];
    if (!img) return;
    sItemImages()[ident] = img;
    if (toolbar) {
        NSToolbar *tb = (__bridge NSToolbar *)toolbar;
        for (NSToolbarItem *item in tb.items) {
            if ([item.itemIdentifier isEqualToString:ident]) {
                item.image = img;
                break;
            }
        }
    }
}

void LCWindowRemoveToolbar(void *nsWindow) {
    if (!nsWindow) return;
    NSWindow *win = (__bridge NSWindow *)nsWindow;
    win.toolbar = nil;
}

void *LCToolbarCreate(const char *identifier) {
    NSString *ident = [NSString stringWithUTF8String:identifier ?: "toolbar"];
    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:ident];
    CFBridgingRetain(tb);
    return (__bridge void *)tb;
}

void LCToolbarRelease(void *toolbar) {
    if (toolbar) CFBridgingRelease(toolbar);
}

void LCToolbarSetDisplayMode(void *toolbar, int mode) {
    if (!toolbar) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    tb.displayMode = (NSToolbarDisplayMode)mode;
}

void LCToolbarSetCustomizable(void *toolbar, int allow) {
    if (!toolbar) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    tb.allowsUserCustomization = allow ? YES : NO;
}

void *LCWindowFromNumber(long windowNumber) {
    for (NSWindow *win in [NSApp windows]) {
        if (win.windowNumber == windowNumber) {
            return (__bridge void *)win;
        }
    }
    return NULL;
}

void *LCToolbarDelegateCreate(void) {
    LCToolbarDelegate *delegate = [[LCToolbarDelegate alloc] init];
    // Manual retain — ARC won't keep it alive past this scope since
    // we're returning a void*. Caller must pass to LCToolbarDelegateRelease.
    CFBridgingRetain(delegate);
    return (__bridge void *)delegate;
}

void LCToolbarDelegateRelease(void *delegate) {
    if (delegate) CFBridgingRelease(delegate);
}

void LCToolbarAttachDelegate(void *toolbar, void *delegate) {
    if (!toolbar || !delegate) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    id<NSToolbarDelegate> del = (__bridge id<NSToolbarDelegate>)delegate;
    tb.delegate = del;
}

void LCToolbarClearDelegate(void *toolbar) {
    if (!toolbar) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    tb.delegate = nil;
}

void LCToolbarInsertItemAtIndex(void *toolbar, const char *itemId, int index) {
    if (!toolbar || !itemId) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    [tb insertItemWithItemIdentifier:ident atIndex:index];
}

void LCToolbarRemoveItemAtIndex(void *toolbar, int index) {
    if (!toolbar) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    [tb removeItemAtIndex:index];
}

void LCToolbarSetItemEnabled(void *toolbar, const char *itemId, int enabled) {
    if (!toolbar || !itemId) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    for (NSToolbarItem *item in tb.items) {
        if ([item.itemIdentifier isEqualToString:ident]) {
            item.enabled = (enabled != 0);
            return;
        }
    }
}

void LCToolbarSetVisible(void *toolbar, int visible) {
    if (!toolbar) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    tb.visible = (visible != 0);
}

int LCToolbarIsVisible(void *toolbar) {
    if (!toolbar) return 0;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    return tb.visible ? 1 : 0;
}

int LCToolbarItemIsEnabled(void *toolbar, const char *itemId) {
    if (!toolbar || !itemId) return 0;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    for (NSToolbarItem *item in tb.items) {
        if ([item.itemIdentifier isEqualToString:ident]) {
            return item.enabled ? 1 : 0;
        }
    }
    return 0;
}

void LCWindowAttachToolbar(void *window, void *toolbar) {
    if (!window || !toolbar) return;
    NSWindow *win = (__bridge NSWindow *)window;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    win.toolbar = tb;
}
