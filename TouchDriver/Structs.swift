//
//  Structs.swift
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-09-02.
//

import Foundation

/*--------------------------------   Enums   ---------------------------------*/

enum InputType {
    case UP
    case DOWN
    case RIGHT_CLICK
    case DBL_CLICK
    case NO_CHANGE
    
    case NOTIFICATION_CENTER
}

enum HIDEventType {
    case TIPSWITCH
    case PRESS
    case CONTACTID
    case XCOORD
    case YCOORD
    case FINGERCOUNT
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
