//
//  simInput.m
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

//---------------------------------------------------------------------------
// Simulate Mouse Events
//---------------------------------------------------------------------------

#include "utils.h"

void simulateClick(int x, int y, ButtonState button) {
    if (button == BTN_DOWN) {
        CGEventRef mouse_press = CGEventCreateMouseEvent(NULL,
                                                         kCGEventLeftMouseDown,
                                                         CGPointMake(x, y),
                                                         kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(mouse_press, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, mouse_press);
        CFRelease(mouse_press);
        //eventNumber++;
    }
    else if (button == BTN_UP) {
        CGEventRef mouse_release = CGEventCreateMouseEvent(NULL,
                                                           kCGEventLeftMouseUp,
                                                           CGPointMake(x, y),
                                                           kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(mouse_release, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, mouse_release);
        CFRelease(mouse_release);
        //eventNumber++;
    }
    else if (button == BTN_RIGHT) {
        CGEventRef mouse_right = CGEventCreateMouseEvent(NULL,
                                                         kCGEventRightMouseDown,
                                                         CGPointMake(x, y),
                                                         kCGMouseButtonRight);
        //CGEventSetIntegerValueField(mouse_press, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, mouse_right);
        CGEventSetType(mouse_right, kCGEventRightMouseUp);
        CGEventPost(kCGHIDEventTap, mouse_right);
        CFRelease(mouse_right);
        //eventNumber++;
    }
    else if (button == BTN_2_CLICK)
    {
        CGEventRef mouse_double = CGEventCreateMouseEvent(NULL,
                                                          kCGEventLeftMouseDown,
                                                          CGPointMake(x, y),
                                                          kCGMouseButtonLeft);
        CGEventSetIntegerValueField(mouse_double, kCGMouseEventClickState, 2);

        CGEventPost(kCGHIDEventTap, mouse_double);
        CGEventSetType(mouse_double, kCGEventLeftMouseUp);
        CGEventPost(kCGHIDEventTap, mouse_double);
        CGEventSetType(mouse_double, kCGEventLeftMouseDown);
        CGEventPost(kCGHIDEventTap, mouse_double);
        CGEventSetType(mouse_double, kCGEventLeftMouseUp);
        CGEventPost(kCGHIDEventTap, mouse_double);
        CFRelease(mouse_double);
    }

    if (button == BTN_NO_CHANGE) {
        CGEventRef move = CGEventCreateMouseEvent(NULL,
                                                  kCGEventLeftMouseDragged,
                                                  CGPointMake(x, y),
                                                  kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(move, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);
        //eventNumber++;
    }

    if (button == BTN_MOVE) {
        CGEventRef move = CGEventCreateMouseEvent(NULL,
                                                  kCGEventMouseMoved,
                                                  CGPointMake(x, y),
                                                  kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(move, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);
        //eventNumber++;
    }
}

#import <ScriptingBridge/ScriptingBridge.h>
#import "SystemEvents.h"

// https://stackoverflow.com/questions/29032726/open-notification-center-programmatically-on-os-x
void openNotificationCenter() {
    static bool firstrun = true;
    static SystemEventsMenuBarItem *item = nil;

    if (firstrun) {
        SystemEventsApplication *systemEventsApp = (SystemEventsApplication *)[[SBApplication alloc] initWithBundleIdentifier:@"com.apple.systemevents"];
        SystemEventsApplicationProcess *sysUIServer = [systemEventsApp.applicationProcesses objectWithName:@"SystemUIServer"];

        for (SystemEventsMenuBar *menuBar in sysUIServer.menuBars) {
            item = [menuBar.menuBarItems objectWithName:@"Notification Center"];
            if (item != nil && [item.name isEqualToString:@"Notification Center"])
                break;
        }
    }

    firstrun = false;
    [item clickAt:nil];
}
