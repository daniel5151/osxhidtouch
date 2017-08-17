//
//  main.m
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

#include "config.h"

// Global Vars
NSLock* gLock = 0;

// Swift Introp
#include "TouchDriver-Swift.h"
Swifty* swift;

#include "setup.h"

int main (int argc, const char*  argv[]) {
    swift = [[Swifty alloc] init];
    gLock = [[NSLock alloc] init];

    InitHIDNotifications(TOUCH_VID, TOUCH_PID);

    printf("To keep this driver alive, run this in the background...\n\n");

    CFRunLoopRun();

    return 0;
}
