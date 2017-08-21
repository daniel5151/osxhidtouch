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

typedef struct HIDElement {
    SInt32             currentValue;
    SInt32             usagePage;
    SInt32             usage;
    IOHIDElementType   type;
    IOHIDElementCookie cookie;
} HIDElement;

#endif
