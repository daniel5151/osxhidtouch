//
//  utils.h
//  HidSample
//
//  Created by Alexander Tarasikov on 23.11.13.
//

#ifndef utils_h
#define utils_h

#include <IOKit/hid/IOHIDLib.h>

//---------------------------------------------------------------------------
// TypeDefs
//---------------------------------------------------------------------------

typedef struct HIDData {
    io_object_t               notification;
    IOHIDDeviceInterface122** hidDeviceInterface;
    IOHIDQueueInterface**     hidQueueInterface;
    CFDictionaryRef           hidElementDictionary;
    CFRunLoopSourceRef        eventSource;
    SInt32                    minx;
    SInt32                    maxx;
    SInt32                    miny;
    SInt32                    maxy;
    UInt8                     buffer[256];
} HIDData;

typedef struct HIDElement {
    SInt32             currentValue;
    SInt32             usagePage;
    SInt32             usage;
    IOHIDElementType   type;
    IOHIDElementCookie cookie;
    HIDData*           owner;
} HIDElement;

typedef enum {
    BTN_UP,
    BTN_DOWN,
    BTN_NO_CHANGE,
    BTN_MOVE,
    BTN_RIGHT,
    BTN_2_CLICK,

    BTN_DUMMY
} ButtonState;

typedef enum {
    INP_TIPSWITCH,
    INP_PRESS,
    INP_CONTACTID,
    INP_XCOORD,
    INP_YCOORD,
    INP_FINGERCOUNT,

    INP_DUMMY
} InputType;

#endif
