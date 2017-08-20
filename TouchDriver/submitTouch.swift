//
//  submitTouch.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

import Foundation

let NUM_TOUCHES: Int = 10

let DOUBLECLICK_DELAY: TimeInterval = 0.2

let NOTIFICATION_CENTER_X_DELTA = 75
let NOTIFICATION_CENTER_Y_DELTA = 50


extension ButtonState : CustomStringConvertible {
    public var description: String {
        let strings = [
            "UP",
            "DOWN",
            "NO_CHANGE",
            "MOVE",
            "RIGHT",
            "DOUBLECLICK",
            ""
        ]
        return strings[Int(rawValue)]
    }
}

extension InputType : CustomStringConvertible {
    public var description: String {
        let strings = [
            "TIPSWITCH",
            "PRESS",
            "CONTACTID",
            "XCOORD",
            "YCOORD",
            "FINGERCOUNT",
            ""
        ]
        return strings[Int(rawValue)]
    }
}

struct Event {
    let finger: Int

    let when: Date
    let type: InputType
    let button: ButtonState

    let input: Int
}

// Pretty Print Events
extension Event : CustomStringConvertible {
    public var description: String {
        let time = when.timeIntervalSince1970
            .truncatingRemainder(dividingBy: 1000)
        let time_str = String(format: "%.4f", time)

        let type_str = String(describing: type)
            .padding(toLength: 10, withPad: " ", startingAt: 0)

        var s = "[\(time_str)] \(finger) | \(type_str)"

        if button == BTN_UP || button == BTN_DOWN { s += " \(button)" }

        if type == INP_XCOORD || type == INP_YCOORD { s += " \(input)" }

        return s
    }
}


// Swift Interop Object
class Swifty : NSObject {

let events = ThingStream<Event>(maxSize: 255)

var pressed: [Bool] = [Bool](repeating: false, count: NUM_TOUCHES)
var fingerAlloc = 1
var fingerCount = 1
var nothingOn = true
var activeFinger = -1

// Bit of heuristics to maintain position of fingers in last_x and last_y
// array if there are multiple fingers, and the last finger on is not the
// last finger taken off, which usually disrupts the index used for the
// last_x and last_y array
// This code recalculates the original indexes, stores them in an array
var indexFixer: [Int] = [Int](0..<NUM_TOUCHES)
func recalculateIndex() {
    var temp = 0
    for i in 0..<self.fingerAlloc {
        while temp < self.fingerAlloc && self.pressed[temp] == false {
            temp += 1
        }

        self.indexFixer[i] = temp < self.fingerAlloc ? temp : -1;

        temp += 1
    }
}

@objc func submitTouch(fingerId: Int, type: InputType, input: Int, button: ButtonState) {
    // [Daniel Prilik]
    // I didn't write this code, but it seems to ge the job done, so i'm
    // leaving it

    var fingerId = fingerId;

    if button != BTN_DOWN { fingerId = self.indexFixer[fingerId] }

    if fingerId == -1 { return }

    if nothingOn { activeFinger = fingerId }

    switch type {
    case INP_TIPSWITCH:
        if input == 0 {
            // Initialize
            self.fingerAlloc = 1
            self.fingerCount = 1
        }

        nothingOn = false
    case INP_CONTACTID:
        self.fingerAlloc = input
    case INP_FINGERCOUNT:
        if nothingOn {
            // sometimes, fingercount is called before timer is, so adjust values
            self.fingerCount = input
            self.fingerAlloc = input
            nothingOn = false
        }

        if input > self.fingerAlloc {
            self.fingerAlloc = input
        }

        if input > self.fingerCount && !nothingOn {
            // The following small loop addresses an issue when a Tipswitch true
            // event isn't generated when fingers are placed. It compares
            // allocated fingers to detected fingers on screen
            for i in 0..<self.fingerAlloc {
                if (!self.pressed[i]) {
                    self.pressed[i] = true
                    break
                }
            }

            // needs recalculation
            recalculateIndex()
        }
        self.fingerCount = input;
    case INP_PRESS:
        if button == BTN_DOWN {
            self.pressed[fingerId] = true
        }

        if button == BTN_UP {
            self.pressed[fingerId] = false

            // calculate original array indexes
            recalculateIndex()
        }
    default:
        // nothing
        break
    }

    if !nothingOn {
        var count = 0; // check for if all fingers are off
        for i in 0..<self.fingerAlloc {
            if self.indexFixer[i] == -1 {
                count += 1
            }
        }
        if (count == self.fingerAlloc) {
            // if true, reassign variables to default values
            nothingOn = true
            self.fingerAlloc = 1;
            for i in 0..<NUM_TOUCHES {
                self.indexFixer[i] = i;
            }
            self.fingerCount = 1;
        }
    }


    // [Daniel Prilik]
    // This is my new implementation

    // Make a "Event" object from what just happened
    let event = Event(
        finger: fingerId,
        when: Date(),
        type: type,
        button: button,
        input: input
    )

    // And pass off control to a function that can handle the events
    self.handleEvent(e: event)
}

////////////////////////////////////////////////////////////////////////////////

// Initially, I thought keeping a record of all the events, and then mapping,
// filtering, and reducing them would be a good way to do gestures...
// At this point, I think it's a better idea to just have something akin to

// var finger_xys: [[(Int32, Int32)]]

// ie. an array of point arrays for each finger, reset to empty when a finger
// is lifted
// So... TODO!

// Track start point of every touch
var start_xy = [(Int32, Int32)](repeating: (0, 0), count: NUM_TOUCHES)

var context_menu_timer: Timer?

func lastXY (finger: Int) -> (Int32, Int32) {
    let fingerEvents = self.events.filter({ $0.finger == finger })
    let last_x = fingerEvents.first{ $0.type == INP_XCOORD }?.input
    let last_y = fingerEvents.first{ $0.type == INP_YCOORD }?.input

    if last_x != nil && last_y != nil {
        return (Int32(last_x!), Int32(last_y!))
    }

    return (-1, -1)
}

func handleEvent(e: Event) {
    print(e)
    if e.button == BTN_UP { print() } // break up chunks of events

    // To make my life a lot easier, i'm just going to focus on one finger
    // right now
    if e.finger != activeFinger {
        self.context_menu_timer?.invalidate()
        return
    }

    let finger = e.finger
    let fingerEvents = self.events.filter({ $0.finger == finger })

    var (curr_x, curr_y) = self.lastXY(finger: finger)
    if e.type == INP_XCOORD { curr_x = Int32(e.input) }
    if e.type == INP_YCOORD { curr_y = Int32(e.input) }

    // Assuming we actually have some coordinates to work with...
    if curr_x != -1 && curr_y != -1 {
        // If there is a press happening
        if e.type == INP_PRESS {

            if e.button == BTN_DOWN {
                self.start_xy[finger] = (curr_x, curr_y)

                // Start a timer to fire off a Right Click event in a half-sec
                self.context_menu_timer = Timer
                    .scheduledTimer(withTimeInterval: 0.5, repeats: false) {
                        (t) in
                        simulateClick(curr_x, curr_y, BTN_UP);
                        simulateClick(curr_x, curr_y, BTN_RIGHT);
                    }
            }

            if e.button == BTN_UP {
                // Invalidate the context-menu timer
                self.context_menu_timer?.invalidate()

                // Check for double-click double-clicked
                if let last_up = (fingerEvents.first{ $0.button == BTN_UP }) {
                    let last_up_dt = e.when.timeIntervalSince(last_up.when)
                    if last_up_dt < DOUBLECLICK_DELAY {
                        simulateClick(curr_x, curr_y, BTN_2_CLICK)
                    }
                }
            }

            // Do the click
            simulateClick(curr_x, curr_y, e.button);
        }

        if e.type == INP_XCOORD || e.type == INP_YCOORD {
            // Check if the current coordinates are far away from the
            // context-menu start coordinates
            if abs(self.start_xy[finger].0 - curr_x) > 10 || abs(self.start_xy[finger].1 - curr_y) > 10 {
                self.context_menu_timer?.invalidate()
            }

            // Check if the user is trying to open notification center
            if abs(self.start_xy[finger].0 - SCREEN_RESX) < 5 {
                if abs(curr_x - self.start_xy[finger].0) > NOTIFICATION_CENTER_X_DELTA && abs(curr_y - self.start_xy[finger].1) < NOTIFICATION_CENTER_Y_DELTA {
                    openNotificationCenter()

                    // This isn't working properly outside of XCode at the moment :(

                    // reset start
                    self.start_xy[finger] = (0, 0)
                }
            }

            // Register the movement
            simulateClick(curr_x, curr_y, BTN_NO_CHANGE);
        }
    }

    // Finally, add the event we just processed to the event history
    self.events.push(val: e)
}

}
