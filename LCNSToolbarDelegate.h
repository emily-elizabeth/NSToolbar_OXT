#ifndef LC_NS_TOOLBAR_DELEGATE_H
#define LC_NS_TOOLBAR_DELEGATE_H

#ifdef __cplusplus
extern "C" {
#endif

void  LCToolbarItemRegister(const char *itemIdentifier, const char *label,
                            const char *iconName, const char *tooltip);
void  LCToolbarItemUnregister(const char *itemIdentifier);
void  LCToolbarItemAppendToOrder(const char *itemIdentifier);
void  LCToolbarItemRemoveFromOrder(const char *itemIdentifier);
void  LCToolbarItemsClear(void);

typedef void (*LCToolbarClickCallback)(const char *itemIdentifier);
void  LCToolbarSetClickCallback(LCToolbarClickCallback cb);
void  LCToolbarClearClickCallback(void);
void  LCToolbarClearClickCallback(void);
int   LCToolbarLastClickLength(void);
void  LCToolbarGetLastClick(char *outBuf, int bufLen);

void *LCToolbarCreate(const char *identifier);
void  LCToolbarRelease(void *toolbar);
void  LCToolbarSetDisplayMode(void *toolbar, int mode);
void  LCToolbarSetCustomizable(void *toolbar, int allow);
void  LCToolbarAttachDelegate(void *toolbar, void *delegate);
void  LCToolbarClearDelegate(void *toolbar);
void  LCToolbarInsertItemAtIndex(void *toolbar, const char *itemId, int index);
void  LCToolbarRemoveItemAtIndex(void *toolbar, int index);
void  LCToolbarSetItemEnabled(void *toolbar, const char *itemId, int enabled);
void  LCToolbarSetVisible(void *toolbar, int visible);
int   LCToolbarIsVisible(void *toolbar);
int   LCToolbarItemIsEnabled(void *toolbar, const char *itemId);

void *LCToolbarDelegateCreate(void);
void  LCToolbarDelegateRelease(void *delegate);

void *LCWindowFromNumber(long windowNumber);
void  LCWindowAttachToolbar(void *window, void *toolbar);

#ifdef __cplusplus
}
#endif

#endif
