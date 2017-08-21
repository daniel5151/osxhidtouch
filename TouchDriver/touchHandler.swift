//
//  submitTouch.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

/*----------------------  Objective C nice Extensions   ----------------------*/

enum ButtonState {
  case
  UP,
  DOWN,
  NO_CHANGE,
  RIGHT,
  DBL_CLICK,

  DUMMY
}

enum InputType {
  case
  TIPSWITCH,
  PRESS,
  CONTACTID,
  XCOORD,
  YCOORD,
  FINGERCOUNT,

  DUMMY
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

    if button == ButtonState.UP || button == ButtonState.DOWN { s += " \(button)" }

    if type == InputType.XCOORD || type == InputType.YCOORD { s += " \(input)" }

    return s
  }
}

/*-----------------------------  Touch struct  -------------------------------*/

struct Touch {
  var x: Int
  var y: Int
  let when: Date

  func distFrom(p: Touch) -> Double {
    return sqrt(pow(Double(x - p.x), 2) + pow(Double(y - p.y), 2))
  }
}

/*-----------------------  Interpret Raw HID Element  ------------------------*/

// [Daniel Prilik]
// I didn't write this code, but it seems to ge the job done, so i'm
// leaving it

func reportHidElement(element: HIDElement) {
  // [Daniel Prilik]
  // At this point, i'm not entire sure if fingerId needs to be static or not
  // So, just to experiment, i'm going to use this hacky tuple to make swapping
  // between fingerId being static and not a fairly simple operation
  var Statics: (fingerId: Int, dummy: Int) = (fingerId: 0, dummy: 0x1337)

//  struct Statics {
//    static var fingerId: Int = 0
//  }
//

  // [Daniel Prilik]
  // This function is HID spec magic, at least for me :)
  // But hey, if it works, who am I to care!

  let scale_x = Double(SCREEN_RESX) / TOUCH_RESX
  let scale_y = Double(SCREEN_RESY) / TOUCH_RESY

  // Make a "Event" object from what just happened
  var event: Event?

  if (element.usagePage == 1 && element.currentValue < 0x10000 && element.cookie != 0x73) {
    let value = Double(element.currentValue & 0xffff)

    if (element.usage == 0x30) { // X
      Statics.fingerId = Int((element.cookie - 21) / 9)
      event = Event(finger: Statics.fingerId,
                    when: Date(),
                    type: InputType.XCOORD,
                    button: ButtonState.NO_CHANGE,
                    input: Int(value * scale_x))
    } else if (element.usage == 0x31) { // Y
      Statics.fingerId = Int((element.cookie - 24) / 9)
      event = Event(finger: Statics.fingerId,
                    when: Date(),
                    type: InputType.YCOORD,
                    button: ButtonState.NO_CHANGE,
                    input: Int(value * scale_y))
    }
  } else if (element.usage == 0x56 && element.currentValue < 8000) {
    // doubleclicktimer
    event = Event(finger: Statics.fingerId,
                  when: Date(),
                  type: InputType.TIPSWITCH,
                  button: ButtonState.DUMMY,
                  input: Int(element.currentValue))

  } else if (Int(element.type.rawValue) == 2) {
    // button

    // finger by cookie value, 15 is 0, 16 is 1, etc
    Statics.fingerId = Int(element.cookie) - 15

    event = Event(finger: Statics.fingerId,
                  when: Date(),
                  type: InputType.PRESS,
                  button: ((element.currentValue == 1) ? ButtonState.DOWN: ButtonState.UP),
                  input: 0)
  } else if (element.usage == 0x51 && element.currentValue != 0) {
    event = Event(finger: Int((element.cookie - 17) / 9),
                  when: Date(),
                  type: InputType.CONTACTID,
                  button: ButtonState.DUMMY,
                  input: Int(element.currentValue / 4))
  } else if (element.usage == 0x54) {
    event = Event(finger: 0,
                  when: Date(),
                  type: InputType.FINGERCOUNT,
                  button: ButtonState.DUMMY,
                  input: Int(element.currentValue))
  }

  // And pass off control to a function that can handle the events
  if event != nil {
    fixEvent(&event!)
    handleEvent(e: event!)

  }
}

// [Daniel Prilik]
// I'm not entirely sure this is neccessary (from personal testing) so i'm
// keeping it seperate, and easily removable
func fixEvent(_ e: inout Event) {
  struct Statics {
    static var pressed: [Bool] = [Bool](repeating: false, count: NUM_TOUCHES)
    static var fingerAlloc = 1
    static var fingerCount = 1
    static var nothingOn = true

    static var indexFixer: [Int] = [Int](0..<NUM_TOUCHES)
  }

  // Bit of heuristics to maintain position of fingers in last_x and last_y
  // array if there are multiple fingers, and the last finger on is not the
  // last finger taken off, which usually disrupts the index used for the
  // last_x and last_y array
  // This code recalculates the original indexes, stores them in an array

  func recalculateIndex() {
    var temp = 0
    for i in 0..<Statics.fingerAlloc {
      while temp < Statics.fingerAlloc && Statics.pressed[temp] == false {
        temp += 1
      }

      Statics.indexFixer[i] = temp < Statics.fingerAlloc ? temp : -1

      temp += 1
    }
  }

  var fingerId = e.finger
  let type = e.type
  let input = e.input
  let button = e.button

  if button != ButtonState.DOWN {
    fingerId = Statics.indexFixer[fingerId]
  }

  if fingerId == -1 { return }

  switch type {
  case InputType.TIPSWITCH:
    if input == 0 {
      // Initialize
      Statics.fingerAlloc = 1
      Statics.fingerCount = 1
    }

    Statics.nothingOn = false
  case InputType.CONTACTID:
    Statics.fingerAlloc = input
  case InputType.FINGERCOUNT:
    if Statics.nothingOn {
      // sometimes, fingercount is called before timer is, so adjust values
      Statics.fingerCount = input
      Statics.fingerAlloc = input
      Statics.nothingOn = false
    }

    if input > Statics.fingerAlloc {
      Statics.fingerAlloc = input
    }

    if input > Statics.fingerCount && !Statics.nothingOn {
      // The following small loop addresses an issue when a Tipswitch true
      // event isn't generated when fingers are placed. It compares
      // allocated fingers to detected fingers on screen
      for i in 0..<Statics.fingerAlloc {
        if (!Statics.pressed[i]) {
          Statics.pressed[i] = true
          break
        }
      }

      // needs recalculation
      recalculateIndex()
    }
    Statics.fingerCount = input
  case InputType.PRESS:
    if button == ButtonState.DOWN {
      Statics.pressed[fingerId] = true
    }

    if button == ButtonState.UP {
      Statics.pressed[fingerId] = false

      // calculate original array indexes
      recalculateIndex()
    }
  default: break
  }

  if !Statics.nothingOn {
    var count = 0; // check for if all fingers are off
    for i in 0..<Statics.fingerAlloc {
      if Statics.indexFixer[i] == -1 {
        count += 1
      }
    }
    if (count == Statics.fingerAlloc) {
      // if true, reassign variables to default values
      Statics.nothingOn = true
      Statics.fingerAlloc = 1
      for i in 0..<NUM_TOUCHES {
        Statics.indexFixer[i] = i
      }
      Statics.fingerCount = 1
    }
  }
}

/*------------------------  Interpret Touch Events  --------------------------*/

// [Daniel Prilik]
// New Implementation starts here

let events = ThingStream<Event>(maxSize: 255)

// Track start point of every touch
var start_xy = [Touch?](repeating: nil, count: NUM_TOUCHES)

// [CONTEXT MENU]
var open_context_menu = false

func handleEvent(e: Event) {
  defer {
    // Always add the event we just processed to the event history!
    events.push(val: e)
  }

  // <debug>
  print(e)
  if e.button == ButtonState.UP { print() } // break up chunks of events
  // </debug>

  if e.finger != 0 {
    // [CONTEXT MENU]
    open_context_menu = false

    // <<< REMOVE THIS ONCE STARTING ON MULTITOUCH GESTURES >>>
    return
  }

  // To make life simple, define some variables related to the current finger
  let finger = e.finger
  let fingerEvents = events.filter({ $0.finger == finger })

  let curr_xy: Touch? = ({
    guard let x = (fingerEvents.first { $0.type == InputType.XCOORD })?.input else {
      return nil
    }
    guard let y = (fingerEvents.first { $0.type == InputType.YCOORD })?.input else {
      return nil
    }

    return Touch(x: Int(x), y: Int(y), when: Date())
  })()

  // Assuming we actually have some coordinates to work with...
  if var curr_xy = curr_xy {
    if e.type == InputType.XCOORD { curr_xy.x = Int(e.input) }
    if e.type == InputType.YCOORD { curr_xy.y = Int(e.input) }

    // If there is a press happening
    if e.type == InputType.PRESS {

      if e.button == ButtonState.DOWN {
        start_xy[finger] = curr_xy

        // [CONTEXT MENU]
        // We potentially want to open the context menu...
        open_context_menu = true
      }

      if e.button == ButtonState.UP {
        // [CONTEXT MENU]
        // Make sure that it was not just a tap
        if let start_xy = start_xy[finger] {
          let timePassed = Date().timeIntervalSince(start_xy.when)
          if open_context_menu && timePassed > CONTEXT_MENU_DELAY {
            simulateClick(touch: curr_xy, button: ButtonState.UP)
            simulateClick(touch: curr_xy, button: ButtonState.RIGHT)
          }
          open_context_menu = false
        }

        // [DOUBLE CLICK]
        if let last_up = (fingerEvents.first { $0.button == ButtonState.UP }) {
          let last_up_dt = e.when.timeIntervalSince(last_up.when)
          if last_up_dt < DOUBLECLICK_DELAY {
            simulateClick(touch: curr_xy, button: ButtonState.DBL_CLICK)
          }
        }
      }

      // Do the click
      simulateClick(touch: curr_xy, button: e.button)
    }

    if e.type == InputType.XCOORD || e.type == InputType.YCOORD {

      // These gestures require a valid start point
      if start_xy[finger] != nil {
        // [CONTEXT MENU]
        // Only open context menu if the pointer has not moved too far from
        // start location
        if curr_xy.distFrom(p: start_xy[finger]!) > 10 {
          open_context_menu = false
        }

        // [NOTIFICATION CENTER]
        if abs(start_xy[finger]!.x - Int(SCREEN_RESX)) < 5 {
          let dx = abs(curr_xy.x - start_xy[finger]!.x)
          let dy = abs(curr_xy.y - start_xy[finger]!.y)
          if dx > NOTIFICATION_CENTER_X_DELTA && dy < NOTIFICATION_CENTER_Y_DELTA {
            simulateClick(touch: curr_xy, button: ButtonState.UP)
            openNotificationCenter()

            // reset start
            start_xy[finger] = nil
          }
        }
      }

      // Register the movement
      simulateClick(touch: curr_xy, button: ButtonState.NO_CHANGE)
    }
  }
}
