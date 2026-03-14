/*
 * LCNSToolbarDelegate.m
 *
 * Implements NSToolbarDelegate in native ObjC and exports a plain C API
 * so LCB can create/destroy the delegate without touching the delegate
 * ABI directly (which caused ffi crashes when done from LCB).
 *
 * Each toolbar is tracked in a per-identifier context (LCToolbarContext)
 * stored in a global registry. Item clicks are delivered to LiveCode via
 * the single global sClickCallback, which receives both the toolbar
 * identifier and the item identifier.
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
// Click callback — single global, receives toolbarId + itemId
// ---------------------------------------------------------------------------

typedef void (*LCToolbarClickCallback)(const char *toolbarIdentifier,
                                       const char *itemIdentifier);
static LCToolbarClickCallback sClickCallback = NULL;

void LCToolbarSetClickCallback(LCToolbarClickCallback cb) {
    sClickCallback = cb;
}

void LCToolbarClearClickCallback(void) {
    sClickCallback = NULL;
}

// ---------------------------------------------------------------------------
// Per-toolbar context
// ---------------------------------------------------------------------------

@interface LCToolbarContext : NSObject
@property (nonatomic, strong) NSString                                     *toolbarId;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *itemMeta;
@property (nonatomic, strong) NSMutableArray<NSString *>                   *itemOrder;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSImage *>   *itemImages;
@end

@implementation LCToolbarContext
- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super init];
    if (self) {
        _toolbarId   = identifier;
        _itemMeta    = [NSMutableDictionary dictionary];
        _itemOrder   = [NSMutableArray array];
        _itemImages  = [NSMutableDictionary dictionary];
    }
    return self;
}
@end

// ---------------------------------------------------------------------------
// Global context registry — keyed by toolbar identifier string
// ---------------------------------------------------------------------------

static NSMutableDictionary<NSString *, LCToolbarContext *> *sContexts(void) {
    static NSMutableDictionary *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

static LCToolbarContext *contextForId(const char *toolbarId) {
    if (!toolbarId) return nil;
    return sContexts()[[NSString stringWithUTF8String:toolbarId]];
}

// ---------------------------------------------------------------------------
// NSToolbarDelegate — one instance per toolbar, holds a weak ref to context
// ---------------------------------------------------------------------------

@interface LCToolbarDelegate : NSObject <NSToolbarDelegate>
@property (nonatomic, strong) NSString *toolbarId;
@end

@implementation LCToolbarDelegate

- (void)toolbarItemClicked:(NSToolbarItem *)item {
    NSString *itemIdent    = item.itemIdentifier;
    NSString *toolbarIdent = self.toolbarId;
    if (!itemIdent || !toolbarIdent) return;
    if (sClickCallback) {
        LCToolbarClickCallback cb = sClickCallback;
        char *itemCopy    = strdup([itemIdent    UTF8String]);
        char *toolbarCopy = strdup([toolbarIdent UTF8String]);
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(toolbarCopy, itemCopy);
            free(itemCopy);
            free(toolbarCopy);
        });
    }
}

// MARK: - NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    LCToolbarContext *ctx = sContexts()[self.toolbarId];
    return ctx ? [ctx.itemOrder copy] : @[];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    LCToolbarContext *ctx = sContexts()[self.toolbarId];
    NSMutableArray *allowed = ctx ? [ctx.itemOrder mutableCopy] : [NSMutableArray array];
    [allowed addObject:NSToolbarFlexibleSpaceItemIdentifier];
    [allowed addObject:NSToolbarSpaceItemIdentifier];
    return [allowed copy];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSString *)itemIdentifier
 willBeInsertedIntoToolbar:(BOOL)flag {

    LCToolbarContext *ctx = sContexts()[self.toolbarId];

    BOOL isSystemItem = [itemIdentifier isEqualToString:NSToolbarSpaceItemIdentifier] ||
                        [itemIdentifier isEqualToString:NSToolbarFlexibleSpaceItemIdentifier] ||
                        [itemIdentifier hasPrefix:@"NSToolbar"] ||
                        ctx == nil ||
                        ctx.itemMeta[itemIdentifier] == nil;
    if (isSystemItem) return nil;

    NSDictionary *meta = ctx.itemMeta[itemIdentifier];

    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    NSString *label = meta[@"label"] ?: itemIdentifier;
    item.label        = label;
    item.paletteLabel = label;
    item.toolTip      = meta[@"tooltip"] ?: @"";

    NSString *iconName = meta[@"iconName"] ?: @"";
    NSImage  *img      = ctx.itemImages[itemIdentifier];
    if (!img && iconName.length > 0) {
        if (@available(macOS 11.0, *)) {
            img = [NSImage imageWithSystemSymbolName:iconName
                             accessibilityDescription:label];
        }
        if (!img) img = [NSImage imageNamed:iconName];
    }
    if (img) item.image = img;

    item.target        = self;
    item.action        = @selector(toolbarItemClicked:);
    item.autovalidates = NO;
    return item;
}

@end

// ---------------------------------------------------------------------------
// Exported C API
// ---------------------------------------------------------------------------

// MARK: Context lifecycle

void LCToolbarContextCreate(const char *toolbarId) {
    if (!toolbarId) return;
    NSString *key = [NSString stringWithUTF8String:toolbarId];
    if (!sContexts()[key]) {
        sContexts()[key] = [[LCToolbarContext alloc] initWithIdentifier:key];
    }
}

void LCToolbarContextDestroy(const char *toolbarId) {
    if (!toolbarId) return;
    NSString *key = [NSString stringWithUTF8String:toolbarId];
    [sContexts() removeObjectForKey:key];
}

// MARK: Item registry

void LCToolbarItemRegister(const char *toolbarId,
                           const char *itemIdentifier,
                           void       *label,
                           const char *iconName,
                           void       *tooltip) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemIdentifier) return;
    NSString *ident      = [NSString stringWithUTF8String:itemIdentifier];
    NSString *labelStr   = label   ? (__bridge NSString *)label   : @"";
    NSString *tooltipStr = tooltip ? (__bridge NSString *)tooltip : @"";
    ctx.itemMeta[ident] = @{
        @"label":    labelStr,
        @"iconName": [NSString stringWithUTF8String:iconName ?: ""],
        @"tooltip":  tooltipStr
    };
}

void LCToolbarItemUnregister(const char *toolbarId, const char *itemIdentifier) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemIdentifier) return;
    [ctx.itemMeta removeObjectForKey:[NSString stringWithUTF8String:itemIdentifier]];
}

void LCToolbarSetItemLabel(void *toolbar, const char *toolbarId,
                           const char *itemId, void *label) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemId || !label) return;
    NSString *ident      = [NSString stringWithUTF8String:itemId];
    NSString *labelStr   = (__bridge NSString *)label;
    NSDictionary *meta   = ctx.itemMeta[ident];
    if (!meta) return;
    ctx.itemMeta[ident] = @{
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

void LCToolbarSetItemTooltip(void *toolbar, const char *toolbarId,
                             const char *itemId, void *tooltip) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemId || !tooltip) return;
    NSString *ident       = [NSString stringWithUTF8String:itemId];
    NSString *tooltipStr  = (__bridge NSString *)tooltip;
    NSDictionary *meta    = ctx.itemMeta[ident];
    if (!meta) return;
    ctx.itemMeta[ident] = @{
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

void LCToolbarItemAppendToOrder(const char *toolbarId, const char *itemIdentifier) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemIdentifier) return;
    NSString *ident = [NSString stringWithUTF8String:itemIdentifier];
    if (![ctx.itemOrder containsObject:ident])
        [ctx.itemOrder addObject:ident];
}

void LCToolbarItemRemoveFromOrder(const char *toolbarId, const char *itemIdentifier) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemIdentifier) return;
    [ctx.itemOrder removeObject:[NSString stringWithUTF8String:itemIdentifier]];
}

void LCToolbarItemsClear(const char *toolbarId) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx) return;
    [ctx.itemMeta   removeAllObjects];
    [ctx.itemOrder  removeAllObjects];
    [ctx.itemImages removeAllObjects];
}

// MARK: Image support

void LCToolbarItemSetImageFile(void *toolbar, const char *toolbarId,
                               const char *itemId, const char *filePath) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemId || !filePath) return;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    NSString *path  = [NSString stringWithUTF8String:filePath];
    NSImage  *img   = [[NSImage alloc] initWithContentsOfFile:path];
    if (!img) return;
    ctx.itemImages[ident] = img;
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

void LCToolbarItemSetNSImage(void *toolbar, const char *toolbarId,
                             const char *itemId, void *nsImage) {
    LCToolbarContext *ctx = contextForId(toolbarId);
    if (!ctx || !itemId || !nsImage) return;
    NSString *ident       = [NSString stringWithUTF8String:itemId];
    NSImage  *img         = (__bridge NSImage *)nsImage;
    ctx.itemImages[ident] = img;
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

// MARK: Toolbar introspection

char *LCToolbarGetItems(void *toolbar) {
    if (!toolbar) return strdup("");
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    NSMutableArray<NSString *> *idents = [NSMutableArray array];
    for (NSToolbarItem *item in tb.items) {
        [idents addObject:item.itemIdentifier];
    }
    return strdup([[idents componentsJoinedByString:@"\n"] UTF8String]);
}

void LCToolbarFreeString(char *str) {
    if (str) free(str);
}

// MARK: Toolbar lifecycle

void *LCToolbarCreate(const char *identifier) {
    NSString *ident = [NSString stringWithUTF8String:identifier ?: "toolbar"];
    NSToolbar *tb   = [[NSToolbar alloc] initWithIdentifier:ident];
    CFBridgingRetain(tb);
    return (__bridge void *)tb;
}

void LCToolbarRelease(void *toolbar) {
    if (toolbar) CFBridgingRelease(toolbar);
}

void LCToolbarSetDisplayMode(void *toolbar, int mode) {
    if (!toolbar) return;
    NSToolbar *tb    = (__bridge NSToolbar *)toolbar;
    tb.displayMode   = (NSToolbarDisplayMode)mode;
}

void LCToolbarSetCustomizable(void *toolbar, int allow) {
    if (!toolbar) return;
    NSToolbar *tb            = (__bridge NSToolbar *)toolbar;
    tb.allowsUserCustomization = allow ? YES : NO;
}

void LCToolbarSetVisible(void *toolbar, int visible) {
    if (!toolbar) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    tb.visible    = (visible != 0);
}

int LCToolbarIsVisible(void *toolbar) {
    if (!toolbar) return 0;
    return ((__bridge NSToolbar *)toolbar).visible ? 1 : 0;
}

void LCToolbarSetItemEnabled(void *toolbar, const char *itemId, int enabled) {
    if (!toolbar || !itemId) return;
    NSToolbar *tb  = (__bridge NSToolbar *)toolbar;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    for (NSToolbarItem *item in tb.items) {
        if ([item.itemIdentifier isEqualToString:ident]) {
            item.enabled = (enabled != 0);
            return;
        }
    }
}

int LCToolbarItemIsEnabled(void *toolbar, const char *itemId) {
    if (!toolbar || !itemId) return 0;
    NSToolbar *tb   = (__bridge NSToolbar *)toolbar;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    for (NSToolbarItem *item in tb.items) {
        if ([item.itemIdentifier isEqualToString:ident])
            return item.enabled ? 1 : 0;
    }
    return 0;
}

void LCToolbarInsertItemAtIndex(void *toolbar, const char *itemId, int index) {
    if (!toolbar || !itemId) return;
    NSToolbar *tb   = (__bridge NSToolbar *)toolbar;
    NSString *ident = [NSString stringWithUTF8String:itemId];
    [tb insertItemWithItemIdentifier:ident atIndex:index];
}

void LCToolbarRemoveItemAtIndex(void *toolbar, int index) {
    if (!toolbar) return;
    [(__bridge NSToolbar *)toolbar removeItemAtIndex:index];
}

// MARK: Delegate lifecycle

void *LCToolbarDelegateCreate(const char *toolbarId) {
    LCToolbarDelegate *delegate = [[LCToolbarDelegate alloc] init];
    delegate.toolbarId = [NSString stringWithUTF8String:toolbarId ?: ""];
    CFBridgingRetain(delegate);
    return (__bridge void *)delegate;
}

void LCToolbarDelegateRelease(void *delegate) {
    if (delegate) CFBridgingRelease(delegate);
}

void LCToolbarAttachDelegate(void *toolbar, void *delegate) {
    if (!toolbar || !delegate) return;
    NSToolbar *tb = (__bridge NSToolbar *)toolbar;
    tb.delegate   = (__bridge id<NSToolbarDelegate>)delegate;
}

void LCToolbarClearDelegate(void *toolbar) {
    if (!toolbar) return;
    ((__bridge NSToolbar *)toolbar).delegate = nil;
}

// MARK: Window

void *LCWindowFromNumber(long windowNumber) {
    for (NSWindow *win in [NSApp windows]) {
        if (win.windowNumber == windowNumber)
            return (__bridge void *)win;
    }
    return NULL;
}

void LCWindowAttachToolbar(void *window, void *toolbar) {
    if (!window || !toolbar) return;
    NSWindow  *win = (__bridge NSWindow *)window;
    NSToolbar *tb  = (__bridge NSToolbar *)toolbar;
    win.toolbar    = tb;
}

void LCWindowRemoveToolbar(void *nsWindow) {
    if (!nsWindow) return;
    ((__bridge NSWindow *)nsWindow).toolbar = nil;
}
