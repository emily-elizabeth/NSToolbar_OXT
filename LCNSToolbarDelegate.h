#ifndef LC_NS_TOOLBAR_DELEGATE_H
#define LC_NS_TOOLBAR_DELEGATE_H

#ifdef __cplusplus
extern "C" {
#endif

// Context lifecycle
void  LCToolbarContextCreate(const char *toolbarId);
void  LCToolbarContextDestroy(const char *toolbarId);

// Item registry
void  LCToolbarItemRegister(const char *toolbarId, const char *itemIdentifier,
                            void *label, const char *iconName, void *tooltip);
void  LCToolbarItemUnregister(const char *toolbarId, const char *itemIdentifier);
void  LCToolbarSetItemLabel(void *toolbar, const char *toolbarId,
                            const char *itemId, void *label);
void  LCToolbarSetItemTooltip(void *toolbar, const char *toolbarId,
                              const char *itemId, void *tooltip);
void  LCToolbarItemAppendToOrder(const char *toolbarId, const char *itemIdentifier);
void  LCToolbarItemRemoveFromOrder(const char *toolbarId, const char *itemIdentifier);
void  LCToolbarItemsClear(const char *toolbarId);

// Image support
void  LCToolbarItemSetImageFile(void *toolbar, const char *toolbarId,
                                const char *itemId, const char *filePath);
void  LCToolbarItemSetNSImage(void *toolbar, const char *toolbarId,
                              const char *itemId, void *nsImage);

// Toolbar introspection
char *LCToolbarGetItems(void *toolbar);
void  LCToolbarFreeString(char *str);

// Click callback
typedef void (*LCToolbarClickCallback)(const char *toolbarIdentifier,
                                       const char *itemIdentifier);
void  LCToolbarSetClickCallback(LCToolbarClickCallback cb);
void  LCToolbarClearClickCallback(void);

// Toolbar lifecycle
void *LCToolbarCreate(const char *identifier);
void  LCToolbarRelease(void *toolbar);
void  LCToolbarSetDisplayMode(void *toolbar, int mode);
void  LCToolbarSetCustomizable(void *toolbar, int allow);
void  LCToolbarSetVisible(void *toolbar, int visible);
int   LCToolbarIsVisible(void *toolbar);
void  LCToolbarSetItemEnabled(void *toolbar, const char *itemId, int enabled);
int   LCToolbarItemIsEnabled(void *toolbar, const char *itemId);
void  LCToolbarInsertItemAtIndex(void *toolbar, const char *itemId, int index);
void  LCToolbarRemoveItemAtIndex(void *toolbar, int index);

// Delegate lifecycle
void *LCToolbarDelegateCreate(const char *toolbarId);
void  LCToolbarDelegateRelease(void *delegate);
void  LCToolbarAttachDelegate(void *toolbar, void *delegate);
void  LCToolbarClearDelegate(void *toolbar);

// Window
void *LCWindowFromNumber(long windowNumber);
void  LCWindowAttachToolbar(void *window, void *toolbar);
void  LCWindowRemoveToolbar(void *nsWindow);

#ifdef __cplusplus
}
#endif

#endif
