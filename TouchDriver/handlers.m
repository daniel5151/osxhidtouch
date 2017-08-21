//
//  handlers.m
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

#include "handlers.h"

#include "config.h"

#include "TouchDriver-Swift.h"
extern Swifty* swift;
extern NSLock* gLock;

//---------------------------------------------------------------------------
// Interpret Events
//---------------------------------------------------------------------------

void submitTouch(int fingerId, InputType type, int input, ButtonState button) {
    // Yeah boi! Let's GET SWIFTY

    [swift submitTouchWithFingerId:fingerId type:type input:input button:button];
}

//---------------------------------------------------------------------------
// Interpret HID events
//---------------------------------------------------------------------------

void reportHidElement(HIDElement *element) {
    if (!element) return;

    [gLock lock];

    const double scale_x = SCREEN_RESX / TOUCH_RESX;
    const double scale_y = SCREEN_RESY / TOUCH_RESY;

    static int fingerId = 0;
    static ButtonState button = BTN_NO_CHANGE;

    if (element->usagePage == 1 && element->currentValue < 0x10000 && element->cookie!= 0x73) {
        short value = element->currentValue & 0xffff;

        if (element->usage == 0x30) { // X
            fingerId = (element->cookie - 21)/9; //int division truncates
            int x = (int)(value * scale_x);
            submitTouch(fingerId, INP_XCOORD, x, BTN_NO_CHANGE);
        }
        else if (element->usage == 0x31) { // Y
            fingerId = (element->cookie - 24)/9; //int division truncates
            int y = (int)(value * scale_y);
            submitTouch(fingerId, INP_YCOORD, y, BTN_NO_CHANGE);
        }

    }

    //doubleclicktimer
    else if (element->usage == 0x56 && element->currentValue < 8000) {
        submitTouch(fingerId, INP_TIPSWITCH, element->currentValue, BTN_DUMMY);
    }

    //button
    else if (element->type == 2) {
        button = (element->currentValue) ? BTN_DOWN : BTN_UP;
        //finger by cookie value, 15 is 0, 16 is 1, etc
        fingerId = element->cookie - 15;

        submitTouch(fingerId, INP_PRESS, 0, button);
    }
    else if (element->usage == 0x51 && element->currentValue!=0) {
        submitTouch((element->cookie - 17)/9, INP_CONTACTID, element->currentValue / 4, BTN_DUMMY);
    }
    else if (element->usage == 0x54) {
        submitTouch(0, INP_FINGERCOUNT, element->currentValue, BTN_DUMMY);
    }

    [gLock unlock];
}
