//
//  HidUtils.h
//  HidSample
//
//  Created by Alexander Tarasikov on 23.11.13.
//  Copyright (c) 2013 Alexander Tarasikov. All rights reserved.
//

#ifndef HidSample_HidUtils_h
#define HidSample_HidUtils_h

#include <IOKit/hid/IOHIDLib.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <IOKit/hid/IOHIDUsageTables.h>
#include <IOKit/hidsystem/IOHIDLib.h>
#include <IOKit/hidsystem/IOHIDShared.h>
#include <IOKit/hidsystem/IOHIDParameter.h>

#include "config.h"

typedef struct HIDData {
    io_object_t                notification;
    IOHIDDeviceInterface122**  hidDeviceInterface;
    IOHIDQueueInterface**      hidQueueInterface;
    CFDictionaryRef            hidElementDictionary;
    CFRunLoopSourceRef         eventSource;
    SInt32                     minx;
    SInt32                     maxx;
    SInt32                     miny;
    SInt32                     maxy;
    UInt8                      buffer[256];
} HIDData;

typedef struct HIDElement {
    SInt32             currentValue;
    SInt32             usagePage;
    SInt32             usage;
    IOHIDElementType   type;
    IOHIDElementCookie cookie;
    HIDData*           owner;
} HIDElement;

static void printHidElement(const char *fname, HIDElement *element) {
    if (!element) return;
    
    const char *hidType = "unknown";

    #define TYPE(__type, name) \
        if (element->type == __type) { hidType = name; break; }
        
    do {
        TYPE(1, "MISC");
        TYPE(2, "Button");
        TYPE(3, "Axis");
        TYPE(4, "ScanCodes");
        TYPE(129, "Output");
        TYPE(257, "Feature");
        TYPE(513, "Collection");
    } while (0);
        
    #undef TYPE
        
    const char *hidUsage = "unknown";
    
    #define USAGE(__page, __usage, name) \
        if (element->usagePage == __page && element->usage == __usage) { \
            hidUsage = name; \
            break; \
        }
    
    do {
        USAGE(0x1, 0x30, "X");
        USAGE(0x1, 0x31, "Y");
        USAGE(0xd, 0x01, "Digitizer");
        USAGE(0xd, 0x02, "Pen");
        USAGE(0xd, 0x03, "Config");
        USAGE(0xd, 0x20, "stylus");
        USAGE(0xd, 0x22, "finger");
        USAGE(0xd, 0x23, "DevSettings");
        USAGE(0xd, 0x30, "pressure");
        USAGE(0xd, 0x32, "InRange");
        USAGE(0xd, 0x3c, "Invert");
        USAGE(0xd, 0x3f, "Azimuth");
        USAGE(0xd, 0x42, "TipSwitch");
        USAGE(0xd, 0x47, "Confidence");
        USAGE(0xd, 0x48, "MT Widght");
        USAGE(0xd, 0x49, "MT Height");
        USAGE(0xd, 0x51, "ContactID");
        USAGE(0xd, 0x53, "DevIndex");
        USAGE(0xd, 0x54, "TouchCount");
        USAGE(0xd, 0x55, "Contact Count Maximum");
        USAGE(0xd, 0x56, "ScanTime");
        USAGE(0xd, kHIDUsage_Dig_Touch, "Touch");
        USAGE(0xd, kHIDUsage_Dig_TouchScreen, "Touchscreen");
    } while (0);
    
    #undef USAGE
    
#if TOUCH_REPORT
    printf("[%s]: <%x:%x> [%s] %s=0x%x (%d)\n",
           fname ? fname : "unknown",
           element->usagePage, element->usage,
           hidType,
           hidUsage,
           element->currentValue,
           element->currentValue);
    fflush(stdout);
#endif
}

#endif

