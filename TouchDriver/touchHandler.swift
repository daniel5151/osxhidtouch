//
//  submitTouch.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

import Foundation

/*------------------------------  Config Vars  -------------------------------*/

let NUM_TOUCHES = 10

let DOUBLECLICK_DELAY: TimeInterval = 0.2

let CONTEXT_MENU_DELAY: TimeInterval = 0.5

let NOTIFICATION_CENTER_X_DELTA = 75
let NOTIFICATION_CENTER_Y_DELTA = 50

/*----------------------  Objective C nice Extensions   ----------------------*/

extension ButtonState: CustomStringConvertible {
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

extension InputType: CustomStringConvertible {
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

func doMouseActionAt(point: Touch, button: ButtonState) {
  simulateClick(x: point.x, y: point.y, button: button)
}

/*-----------------------------  Event struct  -------------------------------*/

struct Event {
  let finger: Int

  let when: Date
  let type: InputType
  let button: ButtonState

  let input: Int
}

// Pretty Print Events
extension Event: CustomStringConvertible {
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

/*-----------------------------  Touch struct  -------------------------------*/

struct Touch {
  var x: Int
  var y: Int
  let when: Date

  func distFrom(p: Touch) -> Double {
    return sqrt(pow(Double(self.x - p.x), 2) + pow(Double(self.y - p.y), 2))
  }
}

/*-------------------  Swift - Objective-C Interop Class  --------------------*/

class Swifty: NSObject {
  let events = ThingStream<Event>(maxSize: 255)

  // [Daniel Prilik]
  // I didn't write this code, but it seems to ge the job done, so i'm
  // leaving it

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

      self.indexFixer[i] = temp < self.fingerAlloc ? temp : -1

      temp += 1
    }
  }

  @objc func submitTouch(fingerId: Int,
                         type: InputType,
                         input: Int,
                         button: ButtonState)
  {
    var fingerId = fingerId

    if button != BTN_DOWN {
      fingerId = self.indexFixer[fingerId]
    }

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
      self.fingerCount = input
    case INP_PRESS:
      if button == BTN_DOWN {
        self.pressed[fingerId] = true
      }

      if button == BTN_UP {
        self.pressed[fingerId] = false

        // calculate original array indexes
        recalculateIndex()
      }
    default: break
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
        self.fingerAlloc = 1
        for i in 0..<NUM_TOUCHES {
          self.indexFixer[i] = i
        }
        self.fingerCount = 1
      }
    }

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

  // [Daniel Prilik]
  // MARK: New Implementation starts here

  // Track start point of every touch
  var start_xy = [Touch?](repeating: nil, count: NUM_TOUCHES)

  // [CONTEXT MENU]
  var open_context_menu = false

  func handleEvent(e: Event) {
    defer {
      // Always add the event we just processed to the event history!
      self.events.push(val: e)
    }

    // <debug>
    print(e)
    if e.button == BTN_UP { print() } // break up chunks of events
    // </debug>

    if e.finger != activeFinger {
      // [CONTEXT MENU]
      self.open_context_menu = false

      // <<< REMOVE THIS ONCE STARTING ON MULTITOUCH GESTURES >>>
      return
    }

    // To make life simple, define some variables related to the current finger
    let finger = e.finger
    let fingerEvents = self.events.filter({ $0.finger == finger })

    let curr_xy: Touch? = ({
      guard let x = (fingerEvents.first { $0.type == INP_XCOORD })?.input else {
        return nil
      }
      guard let y = (fingerEvents.first { $0.type == INP_YCOORD })?.input else {
        return nil
      }

      return Touch(x: Int(x), y: Int(y), when: Date())
    })()

    // Assuming we actually have some coordinates to work with...
    if var curr_xy = curr_xy {
      if e.type == INP_XCOORD { curr_xy.x = Int(e.input) }
      if e.type == INP_YCOORD { curr_xy.y = Int(e.input) }

      // If there is a press happening
      if e.type == INP_PRESS {

        if e.button == BTN_DOWN {
          self.start_xy[finger] = curr_xy

          // [CONTEXT MENU]
          // We potentially want to open the context menu...
          self.open_context_menu = true
        }

        if e.button == BTN_UP {
          // [CONTEXT MENU]
          // Make sure that it was not just a tap
          if let start_xy = self.start_xy[finger] {
            let timePassed = Date().timeIntervalSince(start_xy.when)
            if self.open_context_menu && timePassed > CONTEXT_MENU_DELAY {
              doMouseActionAt(point: curr_xy, button: BTN_UP)
              doMouseActionAt(point: curr_xy, button: BTN_RIGHT)
            }
            self.open_context_menu = false
          }

          // [DOUBLE CLICK]
          if let last_up = (fingerEvents.first { $0.button == BTN_UP }) {
            let last_up_dt = e.when.timeIntervalSince(last_up.when)
            if last_up_dt < DOUBLECLICK_DELAY {
              doMouseActionAt(point: curr_xy, button: BTN_2_CLICK)
            }
          }
        }

        // Do the click
        doMouseActionAt(point: curr_xy, button: e.button)
      }

      if e.type == INP_XCOORD || e.type == INP_YCOORD {

        // These gestures require a valid start point
        if let start_xy = self.start_xy[finger] {
          // [CONTEXT MENU]
          // Only open context menu if the pointer has not moved too far from
          // start location
          if curr_xy.distFrom(p: start_xy) > 10 {
            self.open_context_menu = false
          }

          // [NOTIFICATION CENTER]
          if abs(start_xy.x - Int(SCREEN_RESX)) < 5 {
            let dx = abs(curr_xy.x - start_xy.x)
            let dy = abs(curr_xy.y - start_xy.y)
            if dx > NOTIFICATION_CENTER_X_DELTA && dy < NOTIFICATION_CENTER_Y_DELTA {
              doMouseActionAt(point: curr_xy, button: BTN_UP)
              openNotificationCenter()

              // reset start
              self.start_xy[finger] = nil
            }
          }
        }

        // Register the movement
        doMouseActionAt(point: curr_xy, button: BTN_NO_CHANGE)
      }
    }
  }

}
