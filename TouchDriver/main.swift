//
//  main.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-21.
//

/*---------------------------------  Main  -----------------------------------*/

// Dynamically set screen resolution params
import AppKit
var SCREEN_RESX = NSScreen.main!.frame.size.width
var SCREEN_RESY = NSScreen.main!.frame.size.height

NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                       object: NSApplication.shared,
                                       queue: OperationQueue.main) {
    notification -> Void in
    SCREEN_RESX = NSScreen.main!.frame.size.width
    SCREEN_RESY = NSScreen.main!.frame.size.height
}

// Call legacy objective-c setup code with Swift callback function
InitHIDNotifications(TOUCH_VID, TOUCH_PID) { (element) in
    reportHidElement(element: element!.pointee)
}

print("To keep this driver alive, run this in the background...\n")

CFRunLoopRun()

