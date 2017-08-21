//
//  simInput.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-21.
//

import Foundation

func simulateClick(x: Int, y: Int, button: ButtonState) {
    let point = CGPoint(x: x, y: y)

    switch button {
    case BTN_DOWN:
        let mouse_press = CGEvent(mouseEventSource: nil,
                                  mouseType: CGEventType.leftMouseDown,
                                  mouseCursorPosition: point,
                                  mouseButton: CGMouseButton.left)

        mouse_press?.post(tap: CGEventTapLocation.cghidEventTap)
    case BTN_UP:
        let mouse_release = CGEvent(mouseEventSource: nil,
                                    mouseType: CGEventType.leftMouseUp,
                                    mouseCursorPosition: point,
                                    mouseButton: CGMouseButton.left)

        mouse_release?.post(tap: CGEventTapLocation.cghidEventTap)
    case BTN_RIGHT:
        let mouse_right = CGEvent(mouseEventSource: nil,
                                  mouseType: CGEventType.rightMouseDown,
                                  mouseCursorPosition: point,
                                  mouseButton: CGMouseButton.right)

        mouse_right?.post(tap: CGEventTapLocation.cghidEventTap)
        mouse_right?.type = CGEventType.rightMouseUp
        mouse_right?.post(tap: CGEventTapLocation.cghidEventTap)

    case BTN_2_CLICK:
        let mouse_double = CGEvent(mouseEventSource: nil,
                                   mouseType: CGEventType.leftMouseDown,
                                   mouseCursorPosition: point,
                                   mouseButton: CGMouseButton.left)
        mouse_double?.setIntegerValueField(CGEventField.mouseEventClickState, value: 2)

        mouse_double?.post(tap: CGEventTapLocation.cghidEventTap)
        mouse_double?.type = CGEventType.leftMouseUp
        mouse_double?.post(tap: CGEventTapLocation.cghidEventTap)
    case BTN_NO_CHANGE:
        let move = CGEvent(mouseEventSource: nil,
                           mouseType: CGEventType.leftMouseDragged,
                           mouseCursorPosition: point,
                           mouseButton: CGMouseButton.left)
        move?.post(tap: CGEventTapLocation.cghidEventTap)
    case BTN_MOVE:
        break
    case BTN_DUMMY:
        break
    default:
        break
    }
}

let applescripts: [String: NSAppleScript?] = [
    "notification_center": NSAppleScript(source: """
        tell application "System Events"
            click menu bar item "Notification Center" of menu bar 1 of application process "SystemUIServer"
        end tell
    """)
]

func openNotificationCenter() {
    var error: NSDictionary?
    applescripts["notification_center"]!?.executeAndReturnError(&error)
}

