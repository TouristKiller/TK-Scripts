#import <Cocoa/Cocoa.h>

#include "tk_native_helper.h"

@interface TKDragSource : NSObject <NSDraggingSource>
@end

@implementation TKDragSource
- (NSDragOperation)draggingSession:(NSDraggingSession *)session
    sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    (void)session;
    (void)context;
    return NSDragOperationCopy | NSDragOperationLink | NSDragOperationGeneric;
}
@end

static NSView* resolveSourceView()
{
    id handle = (__bridge id)tknh_main_hwnd();
    if ([handle isKindOfClass:[NSView class]])
        return (NSView*)handle;
    if ([handle isKindOfClass:[NSWindow class]])
        return [(NSWindow*)handle contentView];

    NSWindow* window = [NSApp keyWindow];
    if (!window) window = [NSApp mainWindow];
    if (window) return [window contentView];
    return nil;
}

bool startFileDragMac(const char* utf8_path)
{
    if (!utf8_path || !*utf8_path)
    {
        tknh_log("[TKNativeHelper] leeg pad\n");
        return false;
    }

    @autoreleasepool
    {
        NSString* pathStr = [NSString stringWithUTF8String:utf8_path];
        if (!pathStr)
        {
            tknh_log("[TKNativeHelper] pad-conversie faalde\n");
            return false;
        }

        NSURL* fileURL = [NSURL fileURLWithPath:pathStr];
        if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:pathStr])
        {
            tknh_log("[TKNativeHelper] bestand bestaat niet\n");
            return false;
        }

        NSView* view = resolveSourceView();
        if (!view)
        {
            tknh_log("[TKNativeHelper] geen source view gevonden\n");
            return false;
        }

        NSWindow* window = [view window];
        if (!window)
        {
            tknh_log("[TKNativeHelper] source view heeft geen window\n");
            return false;
        }

        NSEvent* event = [NSApp currentEvent];
        if (!event ||
            (event.type != NSEventTypeLeftMouseDown &&
             event.type != NSEventTypeLeftMouseDragged))
        {
            NSPoint screenLoc = [NSEvent mouseLocation];
            NSRect screenRect = NSMakeRect(screenLoc.x, screenLoc.y, 0, 0);
            NSRect windowRect = [window convertRectFromScreen:screenRect];
            event = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDragged
                                       location:windowRect.origin
                                  modifierFlags:0
                                      timestamp:[[NSProcessInfo processInfo] systemUptime]
                                   windowNumber:[window windowNumber]
                                        context:nil
                                    eventNumber:0
                                     clickCount:1
                                       pressure:1.0];
        }

        if (!event)
        {
            tknh_log("[TKNativeHelper] geen bruikbaar mouse event\n");
            return false;
        }

        NSDraggingItem* item = [[NSDraggingItem alloc] initWithPasteboardWriter:fileURL];
        NSImage* icon = [[NSWorkspace sharedWorkspace] iconForFile:pathStr];
        NSSize size = icon ? [icon size] : NSMakeSize(32, 32);
        if (size.width <= 0 || size.height <= 0) size = NSMakeSize(32, 32);

        NSPoint viewPoint = [view convertPoint:[event locationInWindow] fromView:nil];
        NSRect frame = NSMakeRect(viewPoint.x - size.width / 2.0,
                                  viewPoint.y - size.height / 2.0,
                                  size.width, size.height);
        [item setDraggingFrame:frame contents:icon];

        TKDragSource* source = [[TKDragSource alloc] init];
        NSDraggingSession* session =
            [view beginDraggingSessionWithItems:@[ item ] event:event source:source];
        if (!session)
        {
            tknh_log("[TKNativeHelper] beginDraggingSession faalde\n");
            return false;
        }
        return true;
    }
}
