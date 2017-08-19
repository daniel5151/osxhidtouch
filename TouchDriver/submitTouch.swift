//
//  submitTouch.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

import Foundation

/*
 This is a direct port of the objective-c handler function

 With the handler function *working* in Swift, the new goal is to rewrite it
 to be a *lot* cleaner
 */

let NUM_TOUCHES: Int = 10

let DOUBLECLICK_DELAY: TimeInterval = 0.2

struct Event {
    let fingerId: Int
    
    let when: Date
    let type: InputType
    let button: ButtonState
    
    let input: Int
}

class Swifty : NSObject {
    let events = ThingStream<Event>(maxSize: 50)
    
    var pressed: [Bool] = [Bool](repeating: false, count: NUM_TOUCHES)

    var holdStartCoord = [0, 0]
    var holdNotMoveFar = false
    var last_x = [Int](repeating: 0, count: NUM_TOUCHES)
    var last_y = [Int](repeating: 0, count: NUM_TOUCHES)

    var allocatedFingers = 1
    var fingerCount = 1
    var nothingOn = true

    var holdTime = 0;

    var lastTap: Date = Date(timeIntervalSince1970: 0)
    var tap_delays: [TimeInterval] = [TimeInterval](repeating: 10000, count: 4)
    
    // Bit of heuristics to maintain position of fingers in last_x and last_y
    // array if there are multiple fingers, and the last finger on is not the
    // last finger taken off, which usually disrupts the index used for the
    // last_x and last_y array
    // This code recalculates the original indexes, stores them in an array
    var indexFixer: [Int] = [Int](0..<NUM_TOUCHES)
    func recalculateIndex() {
        var temp = 0
        for i in 0..<allocatedFingers {
            while temp < allocatedFingers && pressed[temp] == false {
                temp += 1
            }
            
            self.indexFixer[i] = temp < allocatedFingers ? temp : -1;
            
            temp += 1
        }
    }

    @objc func submitTouch(fingerId: Int, type: InputType, input: Int, button: ButtonState) {
        var fingerId = fingerId;

        if button != DOWN {
            fingerId = self.indexFixer[fingerId]
        }

        if fingerId == -1 { return }

        switch type {
        case TIPSWITCH:
            if input == 0 {
                // Initialize
                allocatedFingers = 1
                fingerCount = 1
            }

            nothingOn = false
            holdTime = input
        case CONTACTID:
            allocatedFingers = input
        case FINGERCOUNT:
            if nothingOn {
                // sometimes, fingercount is called before timer is, so adjust values
                fingerCount = input
                allocatedFingers = input
                nothingOn = false
            }

            if input > allocatedFingers {
                allocatedFingers = input
            }

            if input > fingerCount && !nothingOn {
                // The following small loop addresses an issue when a Tipswitch true
                // event isn't generated when fingers are placed. It compares
                // allocated fingers to detected fingers on screen
                for i in 0..<allocatedFingers {
                    if (pressed[i] == false) {
                        pressed[i] = true
                        break
                    }
                }

                // needs recalculation
                recalculateIndex()
            }
            fingerCount = input;
        case PRESS:
            // Generate new delay values
            tap_delays[0] = tap_delays[1];
            tap_delays[1] = tap_delays[2];
            tap_delays[2] = tap_delays[3];
            tap_delays[3] = 0 - lastTap.timeIntervalSinceNow

            if (tap_delays[3] > DOUBLECLICK_DELAY) {
                tap_delays[0] = 10000
                tap_delays[1] = 10000
                tap_delays[2] = 10000
                tap_delays[3] = 10000
                lastTap = Date(timeIntervalSince1970: 0)
            }

            lastTap = Date()

            // dragging: coordinate has to be assigned by now, so safe
            if button == DOWN {
                pressed[fingerId] = true

                holdStartCoord[0] = last_x[fingerId]
                holdStartCoord[1] = last_y[fingerId]
                holdNotMoveFar = true
            }

            if (last_x[fingerId] > 0 && last_y[fingerId] > 0) {
                if (button == UP && /*tap_delays[0] < DELAY &&*/ tap_delays[1] < DOUBLECLICK_DELAY && tap_delays[2] < DOUBLECLICK_DELAY && tap_delays[3] < DOUBLECLICK_DELAY) {

                    simulateClick(Int32(last_x[fingerId]), Int32(last_y[fingerId]), DOUBLECLICK);

                    tap_delays[0] = 10000
                    tap_delays[1] = 10000
                    tap_delays[2] = 10000
                    tap_delays[3] = 10000
                    lastTap = Date(timeIntervalSince1970: 0)
                } else {
                    simulateClick(Int32(last_x[fingerId]), Int32(last_y[fingerId]), button);
                }
            }

            if (button == UP) { //cleanup
                if last_x[fingerId] > 0 && last_y[fingerId] > 0 && holdTime > 7500 && holdNotMoveFar {
                    simulateClick(Int32(last_x[fingerId]), Int32(last_y[fingerId]), RIGHT);
                }

                holdNotMoveFar = false
                holdStartCoord = [0, 0]

                holdTime = 0
                pressed[fingerId] = false
                last_x[fingerId] = 0
                last_y[fingerId] = 0

                // calculate original array indexes
                recalculateIndex()
            }
        case XCOORD, YCOORD:
            if type == XCOORD { last_x[fingerId] = input }
            if type == YCOORD { last_y[fingerId] = input }

            if pressed[fingerId] && last_x[fingerId] > 0 && last_y[fingerId] > 0 {
                simulateClick(Int32(last_x[fingerId]), Int32(last_y[fingerId]), NO_CHANGE);
            }

            // Holding a finger has to be within 10 pixels
            if abs(last_x[fingerId] - holdStartCoord[0]) > 10 || abs(last_y[fingerId] - holdStartCoord[1]) > 10 {
                holdNotMoveFar = false;
            }
        default:
            // nothing
            break
        }

        if !nothingOn {
            var count = 0; //check for if all fingers are off
            for i in 0..<allocatedFingers {
                if self.indexFixer[i] == -1 {
                    count += 1
                }
            }
            if (count == allocatedFingers) {
                //if true, reassign variables to default values

                nothingOn = true
                allocatedFingers = 1;
                for i in 0..<NUM_TOUCHES {
                    self.indexFixer[i] = i;
                    last_x[i] = 0;
                    last_y[i] = 0;
                }
                fingerCount = 1;
            }
        }
    }

    @objc func test() {
//        print("get swifty");
    }
}
