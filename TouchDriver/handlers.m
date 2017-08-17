//
//  handlers.m
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

#include "handlers.h"

#include "config.h"
#include "simInput.h"

#include "TouchDriver-Swift.h"
extern Swifty* swift;
extern NSLock* gLock;

//---------------------------------------------------------------------------
// Interpret Events
//---------------------------------------------------------------------------

// Bit of heuristics to maintain position of fingers in last_x and last_y array
// if there are multiple fingers, and the last finger on is not the last finger
// taken off, which usually disrupts the index used for the last_x and last_y
// array
// This code recalculates the original indexes, stores them in an array

void recalculateIndex(bool pressed[], short indexFixer[], short allocFingers) {
    short temp = 0;
    for (int i = 0; i< allocFingers; i++) {
        if (pressed[temp] == 0) {
            temp++;
            while(pressed[temp] == 0 && temp < allocFingers)
                temp++;
        }
        if (temp < allocFingers)
            indexFixer[i] = temp;
        else {
            indexFixer[i]=-1;
        }
        temp++;
    }
}

void submitTouch(int fingerId, InputType type, int input, ButtonState button) {
    [swift test];

#if TOUCH_REPORT
    printf("%s: <%d, %d> state=%d\n", __func__, fingerId, type, button);
#endif
    static int last_x[NUM_TOUCHES] = { 0 };
    static int last_y[NUM_TOUCHES] = { 0 };
    static bool pressed[NUM_TOUCHES] = { 0 };
    static int holdStartCoord[2] = { 0, 0 };
    static short indexFixer[NUM_TOUCHES] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9
    };
    static bool holdNotMoveFar = 0;
    static short holdTime = 0;
    static short allocatedFingers = 1;
    static short fingerCount = 1;
    static bool nothingOn = 1;

    static NSDate* lastTap = 0;
    static NSTimeInterval tap_delays[4] = {10000};

    static const NSTimeInterval DOUBLECLICK_DELAY = 0.2; // in seconds

    if (button !=DOWN) {
        fingerId = indexFixer[fingerId];
    }

    if (type == TIPSWITCH) {
        if (input == 0) { //initialize
            allocatedFingers = 1;
            fingerCount = 1;
        }
        nothingOn = 0;
        holdTime = input;
    }
    else if (type == CONTACTID) {
        allocatedFingers = input;
    }
    else if (type == FINGERCOUNT) {
        if (nothingOn) {
            //sometimes, fingercount is called before timer is, so adjust values
            fingerCount = input;
            allocatedFingers = input;
            nothingOn = 0;
        }
        if (input > allocatedFingers)
            allocatedFingers = input;

        if (input > fingerCount && !nothingOn) {
            // The following small loop addresses an issue when a Tipswitch true
            // event isn't generated when fingers are placed. It compares
            // allocated fingers to detected fingers on screen
            for (int i = 0; i < allocatedFingers; i++) {
                if (pressed[i] == 0) {
                    pressed[i] = 1;
                    i = allocatedFingers; //b reak
                }
            }
            //needs recalculation
            recalculateIndex(pressed, indexFixer, allocatedFingers);
        }
        fingerCount = input;
    }
    else if (type == PRESS) {
        // Generate new delay values
        tap_delays[0] = tap_delays[1];
        tap_delays[1] = tap_delays[2];
        tap_delays[2] = tap_delays[3];
        tap_delays[3] = - [lastTap timeIntervalSinceNow];

        if (tap_delays[3] > DOUBLECLICK_DELAY) {
            tap_delays[0] = tap_delays[1] = tap_delays[2] = tap_delays[3] = 10000;
            lastTap = 0;
        }

        lastTap = [NSDate date];

#if TOUCH_REPORT
        printf("doubleclick delays: [%f %f %f %f]\n", tap_delays[0], tap_delays[1], tap_delays[2], tap_delays[3]);
#endif

        // dragging: coordinate has to be assigned by now, so safe
        if (button == DOWN) {
            pressed[fingerId] = 1;

            holdStartCoord[0] = last_x[fingerId];
            holdStartCoord[1] = last_y[fingerId];
            holdNotMoveFar = true;
        }

        if (last_x[fingerId] >0 && last_y[fingerId] > 0) {
            if (button == UP && /*tap_delays[0] < DELAY &&*/ tap_delays[1] < DOUBLECLICK_DELAY && tap_delays[2] < DOUBLECLICK_DELAY && tap_delays[3] < DOUBLECLICK_DELAY) {

                printf("DoubleClick!\n");

                simulateClick(last_x[fingerId], last_y[fingerId], DOUBLECLICK);
                tap_delays[0] = tap_delays[1] = tap_delays[2] = tap_delays[3] = 10000;
                lastTap = 0;

            } else {
                simulateClick(last_x[fingerId], last_y[fingerId], button);
            }
        }

        if (button == UP) { //cleanup
            if (last_x[fingerId] > 0 && last_y[fingerId] > 0 &&
                holdTime > 7500 && holdNotMoveFar
            ) {
                simulateClick(last_x[fingerId], last_y[fingerId], RIGHT);
            }

            holdNotMoveFar = false;
            holdStartCoord[0] = 0;
            holdStartCoord[1] = 0;

            holdTime = 0;
            pressed[fingerId] = 0;
            last_x[fingerId] = last_y[fingerId] = 0;

            // calculate original array indexes
            recalculateIndex(pressed, indexFixer, allocatedFingers);
        }
    }
    else {
        //assert(type ==XCOORD || type == YCOORD);

        if (type == XCOORD) {
            last_x[fingerId] = input;
        }
        if (type == YCOORD) {
            last_y[fingerId] = input;
        }
        if (pressed[fingerId] && last_x[fingerId] > 0 && last_y[fingerId] > 0) {
            simulateClick(last_x[fingerId], last_y[fingerId], NO_CHANGE);
        }

        // Holding a finger has to be within 10 pixels
        if (abs(last_x[fingerId] - holdStartCoord[0]) > 10 ||
            abs(last_y[fingerId] - holdStartCoord[1]) > 10)
        {
            holdNotMoveFar = false;
        }
    }

    if (!nothingOn) {
        short count = 0; //check for if all fingers are off
        for (int i = 0; i <= allocatedFingers; i++) {
            if (indexFixer[i]==-1)
                count++;
        }
        if (count == allocatedFingers) {
            //if true, reassign variables to default values

            nothingOn = 1;
            allocatedFingers = 1;
            for (int i = 0; i < NUM_TOUCHES; i++) {
                indexFixer[i] = i;
                last_x[i] = 0;
                last_y[i] = 0;
            }
            fingerCount = 1;
        }
    }
}

//---------------------------------------------------------------------------
// Interpret HID events
//---------------------------------------------------------------------------

void reportHidElement(HIDElement *element) {
    if (!element) return;

    [gLock lock];

    static float scale_x = SCREEN_RESX / 3966.0;
    static float scale_y = SCREEN_RESY / 2239.0;

    static int fingerId = 0;
    static ButtonState button = NO_CHANGE;

    if (element->usagePage == 1 && element->currentValue < 0x10000 && element->cookie!= 0x73) {
        short value = element->currentValue & 0xffff;

        if (element->usage == 0x30) { // X
            fingerId = (element->cookie - 21)/9; //int division truncates
            int x = (int)(value * scale_x);
            submitTouch(fingerId, XCOORD, x, NO_CHANGE);
        }
        else if (element->usage == 0x31) { // Y
            fingerId = (element->cookie - 24)/9; //int division truncates
            int y = (int)(value * scale_y);
            submitTouch(fingerId, YCOORD, y, NO_CHANGE);
        }

    }

    //doubleclicktimer
    else if (element->usage == 0x56 && element->currentValue < 8000) {
        submitTouch(fingerId, TIPSWITCH, element->currentValue, RIGHT);
    }

    //button
    else if (element->type == 2) {
        button = (element->currentValue) ? DOWN : UP;
        //finger by cookie value, 15 is 0, 16 is 1, etc
        fingerId = element->cookie - 15;

        submitTouch(fingerId, PRESS, 0, button);
    }
    else if (element->usage == 0x51 && element->currentValue!=0) {
        submitTouch((element->cookie - 17)/9, CONTACTID, element->currentValue / 4, NO_CHANGE);
    }
    else if (element->usage == 0x54) {
        submitTouch(0, FINGERCOUNT, element->currentValue, NO_CHANGE);
    }

    [gLock unlock];
}
