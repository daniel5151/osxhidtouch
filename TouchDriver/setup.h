//
//  setup.h
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

#ifndef setup_h
#define setup_h

#import <Foundation/Foundation.h>

#include <IOKit/IOKitLib.h>

#include "utils.h"

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

void InitHIDNotifications(SInt32, SInt32, void(*)(HIDElement*));

void HIDDeviceAdded(void* refCon, io_iterator_t iterator);
void DeviceNotification(
    void*        refCon,
    io_service_t service,
    natural_t    messageType,
    void*        messageArgument
);
bool FindHIDElements(HIDData* hidDataRef);
bool SetupQueue(HIDData* hidDataRef);
void QueueCallbackFunction(
    void*    target,
    IOReturn result,
    void*    refcon,
    void*    sender
);

#endif
