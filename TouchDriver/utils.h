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
    UP,
    DOWN,
    NO_CHANGE,
    MOVE,
    RIGHT,
    DOUBLECLICK
} ButtonState;

static inline const char *ButtonState_toString(ButtonState f) {
    static const char *strings[] = {
        "UP",
        "DOWN",
        "NO_CHANGE",
        "MOVE",
        "RIGHT",
        "DOUBLECLICK"
    };

    return strings[f];
}

typedef enum {
    TIPSWITCH,
    PRESS,
    CONTACTID,
    XCOORD,
    YCOORD,
    FINGERCOUNT
} InputType;

static inline const char *InputType_toString(InputType f) {
    static const char *strings[] = {
        "TIPSWITCH",
        "PRESS",
        "CONTACTID",
        "XCOORD",
        "YCOORD",
        "FINGERCOUNT"
    };

    return strings[f];
}

#endif
