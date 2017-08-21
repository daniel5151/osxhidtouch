//
//  setup.h.m
//  TouchDriver
//
//  Created by Daniel Prilik on 2017-08-17.
//

// [Daniel Prilik]
// This code is magical. I'm not going to touch it just yet.

#include "setup.h"

#include "utils.h"

//---------------------------------------------------------------------------
// Globals
//---------------------------------------------------------------------------
static IONotificationPortRef gNotifyPort = NULL;
static io_iterator_t         gAddedIter  = 0;

void(*reportHidElementFn)(HIDElement *element);

//---------------------------------------------------------------------------
// Debug
//---------------------------------------------------------------------------
void printHidElement(const char *fname, HIDElement *element) {
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

    printf("[%s]: <%x:%x> [%s] %s=0x%x (%d)\n",
           fname ? fname : "unknown",
           element->usagePage, element->usage,
           hidType,
           hidUsage,
           element->currentValue,
           element->currentValue);
    fflush(stdout);
}


//---------------------------------------------------------------------------
// InitHIDNotifications
//
// This routine just creates our master port for IOKit and turns around
// and calls the routine that will alert us when a HID Device is plugged in.
//---------------------------------------------------------------------------

void InitHIDNotifications(SInt32 vendorID, SInt32 productID, void(*reportHidElement)(HIDElement*))
{
    reportHidElementFn = reportHidElement;
    
    CFMutableDictionaryRef     matchingDict;
    CFNumberRef                 refProdID;
    CFNumberRef                 refVendorID;
    mach_port_t         masterPort;
    kern_return_t        kr;

    // first create a master_port for my task
    //
    kr = IOMasterPort(bootstrap_port, &masterPort);
    if (kr || !masterPort)
        return;

    // Create a notification port and add its run loop event source to our run loop
    // This is how async notifications get set up.
    //
    gNotifyPort = IONotificationPortCreate(masterPort);
    CFRunLoopAddSource(    CFRunLoopGetCurrent(),
                       IONotificationPortGetRunLoopSource(gNotifyPort),
                       kCFRunLoopDefaultMode);

    // Create the IOKit notifications that we need
    //
    /* Create a matching dictionary that (initially) matches all HID devices. */
    matchingDict = IOServiceMatching(kIOHIDDeviceKey);

    if (!matchingDict)
        return;

    /* Create objects for product and vendor IDs. */
    refProdID = CFNumberCreate (kCFAllocatorDefault, kCFNumberIntType, &productID);
    refVendorID = CFNumberCreate (kCFAllocatorDefault, kCFNumberIntType, &vendorID);

    /* Add objects to matching dictionary and clean up. */
    CFDictionarySetValue (matchingDict, CFSTR (kIOHIDVendorIDKey), refVendorID);
    CFDictionarySetValue (matchingDict, CFSTR (kIOHIDProductIDKey), refProdID);

    CFRelease(refProdID);
    CFRelease(refVendorID);

    // Now set up a notification to be called when a device is first matched by I / O Kit.
    // Note that this will not catch any devices that were already plugged in so we take
    // care of those later.
    kr = IOServiceAddMatchingNotification(gNotifyPort,            // notifyPort
                                          kIOFirstMatchNotification,    // notificationType
                                          matchingDict,            // matching
                                          HIDDeviceAdded,        // callback
                                          NULL,                // refCon
                                          &gAddedIter            // notification
                                          );

    if (kr != kIOReturnSuccess)
        return;

    HIDDeviceAdded(NULL, gAddedIter);
}

//---------------------------------------------------------------------------
// HIDDeviceAdded
//
// This routine is the callback for our IOServiceAddMatchingNotification.
// When we get called we will look at all the devices that were added and
// we will:
//
// Create some private data to relate to each device
//
// Submit an IOServiceAddInterestNotification of type kIOGeneralInterest for
// this device using the refCon field to store a pointer to our private data.
// When we get called with this interest notification, we can grab the refCon
// and access our private data.
//---------------------------------------------------------------------------

void HIDDeviceAdded(void* refCon, io_iterator_t iterator)
{
    io_object_t               hidDevice          = 0;
    IOCFPlugInInterface**     plugInInterface    = NULL;
    IOHIDDeviceInterface122** hidDeviceInterface = NULL;
    HRESULT                   result             = S_FALSE;
    HIDData*                  hidDataRef         = NULL;
    IOReturn                  kr;
    SInt32                    score;
    bool                      pass;

    /* Interate through all the devices that matched */
    while (0 != (hidDevice = IOIteratorNext(iterator)))
    {
        // Create the CF plugin for this device
        kr = IOCreatePlugInInterfaceForService(hidDevice, kIOHIDDeviceUserClientTypeID,
                                               kIOCFPlugInInterfaceID, &plugInInterface, &score);

        if (kr != kIOReturnSuccess)
            goto HIDDEVICEADDED_NONPLUGIN_CLEANUP;

        /* Obtain a device interface structure (hidDeviceInterface). */
        result = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID122),
                                                    (void* )&hidDeviceInterface);

        // Got the interface
        if ((result == S_OK) && hidDeviceInterface)
        {
            /* Create a custom object to keep data around for later. */
            hidDataRef = malloc(sizeof(HIDData));
            bzero(hidDataRef, sizeof(HIDData));

            hidDataRef->hidDeviceInterface = hidDeviceInterface;

            /* Open the device interface. */
            result = (*(hidDataRef->hidDeviceInterface))->open (hidDataRef->hidDeviceInterface, kIOHIDOptionsTypeSeizeDevice);

            if (result != S_OK)
                goto HIDDEVICEADDED_FAIL;

            /* Find the HID elements for this device and set up a receive queue. */
            pass = FindHIDElements(hidDataRef);
            pass = SetupQueue(hidDataRef);
            
            /* Register an interest in finding out anything that happens with this device (disconnection, for example) */
            IOServiceAddInterestNotification(
                                             gNotifyPort,        // notifyPort
                                             hidDevice,            // service
                                             kIOGeneralInterest,        // interestType
                                             DeviceNotification,        // callback
                                             hidDataRef,            // refCon
                                             &(hidDataRef->notification)    // notification
                                             );

            goto HIDDEVICEADDED_CLEANUP;
        }

    HIDDEVICEADDED_FAIL:
        // Failed to allocated a UPS interface.  Do some cleanup
        if (hidDeviceInterface)
        {
            (*hidDeviceInterface)->Release(hidDeviceInterface);
            hidDeviceInterface = NULL;
        }

        if (hidDataRef)
            free (hidDataRef);

    HIDDEVICEADDED_CLEANUP:
        // Clean up
        (*plugInInterface)->Release(plugInInterface);

    HIDDEVICEADDED_NONPLUGIN_CLEANUP:
        IOObjectRelease(hidDevice);
    }
}

//---------------------------------------------------------------------------
// DeviceNotification
//
// This routine will get called whenever any kIOGeneralInterest notification
// happens.
//---------------------------------------------------------------------------

void DeviceNotification(void*         refCon,
                               io_service_t     service,
                               natural_t     messageType,
                               void*         messageArgument)
{
    kern_return_t    kr;
    HIDData*        hidDataRef = (HIDData*) refCon;

    /* Check to see if a device went away and clean up. */
    if ((hidDataRef != NULL) &&
        (messageType == kIOMessageServiceIsTerminated))
    {
        if (hidDataRef->hidQueueInterface != NULL)
        {
            kr = (*(hidDataRef->hidQueueInterface))->stop((hidDataRef->hidQueueInterface));
            kr = (*(hidDataRef->hidQueueInterface))->dispose((hidDataRef->hidQueueInterface));
            kr = (*(hidDataRef->hidQueueInterface))->Release (hidDataRef->hidQueueInterface);
            hidDataRef->hidQueueInterface = NULL;
        }

        if (hidDataRef->hidDeviceInterface != NULL)
        {
            kr = (*(hidDataRef->hidDeviceInterface))->close (hidDataRef->hidDeviceInterface);
            kr = (*(hidDataRef->hidDeviceInterface))->Release (hidDataRef->hidDeviceInterface);
            hidDataRef->hidDeviceInterface = NULL;
        }

        if (hidDataRef->notification)
        {
            kr = IOObjectRelease(hidDataRef->notification);
            hidDataRef->notification = 0;
        }

    }
}

//---------------------------------------------------------------------------
// FindHIDElements
//---------------------------------------------------------------------------

bool acceptHidElement(HIDElement *element) {
//    // DEBUG
//    printHidElement("acceptHidElement", element);

    switch (element->usagePage) {
        case kHIDPage_GenericDesktop:
            switch (element->usage) {
                case kHIDUsage_GD_X:
                case kHIDUsage_GD_Y:
                    return true;
            }
            break;
        case kHIDPage_Button:
            switch (element->usage) {
                case kHIDUsage_Button_1:
                    return true;
                    break;
            }
            break;
        case kHIDPage_Digitizer:
            return true;
            break;
    }

    return false;
}

bool FindHIDElements(HIDData* hidDataRef)
{
    CFArrayRef              elementArray    = NULL;
    CFMutableDictionaryRef  hidElements     = NULL;
    CFMutableDataRef        newData         = NULL;
    CFNumberRef             number        = NULL;
    CFDictionaryRef         element        = NULL;
    HIDElement              newElement;
    IOReturn                ret        = kIOReturnError;
    unsigned                i;

    if (!hidDataRef)
        return false;

    /* Create a mutable dictionary to hold HID elements. */
    hidElements = CFDictionaryCreateMutable(
                                            kCFAllocatorDefault,
                                            0,
                                            &kCFTypeDictionaryKeyCallBacks,
                                            &kCFTypeDictionaryValueCallBacks);
    if (!hidElements)
        return false;

    // Let's find the elements
    ret = (*hidDataRef->hidDeviceInterface)->copyMatchingElements(
                                                                  hidDataRef->hidDeviceInterface,
                                                                  NULL,
                                                                  &elementArray);


    if ((ret != kIOReturnSuccess) || !elementArray)
        goto FIND_ELEMENT_CLEANUP;

    //CFShow(elementArray);

    /* Iterate through the elements and read their values. */
    for (i = 0; i < CFArrayGetCount(elementArray); i++)
    {
        element = (CFDictionaryRef) CFArrayGetValueAtIndex(elementArray, i);
        if (!element)
            continue;

        bzero(&newElement, sizeof(HIDElement));

        /* Read the element's usage page (top level category describing the type of
         element---kHIDPage_GenericDesktop, for example) */
        number = (CFNumberRef)CFDictionaryGetValue(element, CFSTR(kIOHIDElementUsagePageKey));
        if (!number) continue;
        CFNumberGetValue(number, kCFNumberSInt32Type, &newElement.usagePage);

        /* Read the element's usage (second level category describing the type of
         element---kHIDUsage_GD_Keyboard, for example) */
        number = (CFNumberRef)CFDictionaryGetValue(element, CFSTR(kIOHIDElementUsageKey));
        if (!number) continue;
        CFNumberGetValue(number, kCFNumberSInt32Type, &newElement.usage);

        /* Read the cookie (unique identifier) for the element */
        number = (CFNumberRef)CFDictionaryGetValue(element, CFSTR(kIOHIDElementCookieKey));
        if (!number) continue;
        CFNumberGetValue(number, kCFNumberIntType, &(newElement.cookie));

        /* Determine what type of element this is---button, Axis, etc. */
        number = (CFNumberRef)CFDictionaryGetValue(element, CFSTR(kIOHIDElementTypeKey));
        if (!number) continue;
        CFNumberGetValue(number, kCFNumberIntType, &(newElement.type));

        /* Pay attention to X / Y coordinates of a pointing device and
         the first mouse button.  For other elements, go on to the
         next element. */

        if (!acceptHidElement(&newElement)) {
            continue;
        }

        /* Add this element to the hidElements dictionary. */
        newData = CFDataCreateMutable(kCFAllocatorDefault, sizeof(HIDElement));
        if (!newData) continue;
        bcopy(&newElement, CFDataGetMutableBytePtr(newData), sizeof(HIDElement));

        number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &newElement.cookie);
        if (!number)  continue;
        CFDictionarySetValue(hidElements, number, newData);
        CFRelease(number);
        CFRelease(newData);
    }

FIND_ELEMENT_CLEANUP:
    if (elementArray) CFRelease(elementArray);

    if (CFDictionaryGetCount(hidElements) == 0)
    {
        CFRelease(hidElements);
        hidElements = NULL;
    }
    else
    {
        hidDataRef->hidElementDictionary = hidElements;
    }

    return hidDataRef->hidElementDictionary;
}

//---------------------------------------------------------------------------
// SetupQueue
//---------------------------------------------------------------------------
bool SetupQueue(HIDData* hidDataRef)
{
    CFIndex           count    = 0;
    CFIndex           i        = 0;
    CFMutableDataRef* elements = NULL;
    CFStringRef *     keys     = NULL;
    IOReturn          ret;
    HIDElement*    tempHIDElement    = NULL;
    bool        cookieAdded     = false;
    bool                boolRet         = true;

    if (!hidDataRef->hidElementDictionary || (((count = CFDictionaryGetCount(hidDataRef->hidElementDictionary)) <= 0)))
        return false;

    keys     = (CFStringRef *)malloc(sizeof(CFStringRef) * count);
    elements     = (CFMutableDataRef *)malloc(sizeof(CFMutableDataRef) * count);

    CFDictionaryGetKeysAndValues(hidDataRef->hidElementDictionary, (const void* *)keys, (const void* *)elements);

    hidDataRef->hidQueueInterface = (*hidDataRef->hidDeviceInterface)->allocQueue(hidDataRef->hidDeviceInterface);
    if (!hidDataRef->hidQueueInterface)
    {
        boolRet = false;
        goto SETUP_QUEUE_CLEANUP;
    }

    ret = (*hidDataRef->hidQueueInterface)->create(hidDataRef->hidQueueInterface, 0, 8);
    if (ret != kIOReturnSuccess)
    {
        boolRet = false;
        goto SETUP_QUEUE_CLEANUP;
    }

    for (i = 0; i < count; i++)
    {
        if (!elements[i] ||
            !(tempHIDElement = (HIDElement*)CFDataGetMutableBytePtr(elements[i])))
            continue;

//        // DEBUG
//        printHidElement("SetupQueue", tempHIDElement);

        if ((tempHIDElement->type < kIOHIDElementTypeInput_Misc) || (tempHIDElement->type > kIOHIDElementTypeInput_ScanCodes))
            continue;

        ret = (*hidDataRef->hidQueueInterface)->addElement(hidDataRef->hidQueueInterface, tempHIDElement->cookie, 0);

        if (ret == kIOReturnSuccess)
            cookieAdded = true;
    }

    if (cookieAdded)
    {
        ret = (*hidDataRef->hidQueueInterface)->createAsyncEventSource(hidDataRef->hidQueueInterface, &hidDataRef->eventSource);
        if (ret != kIOReturnSuccess)
        {
            boolRet = false;
            goto SETUP_QUEUE_CLEANUP;
        }

        ret = (*hidDataRef->hidQueueInterface)->setEventCallout(hidDataRef->hidQueueInterface, QueueCallbackFunction, NULL, hidDataRef);
        if (ret != kIOReturnSuccess)
        {
            boolRet = false;
            goto SETUP_QUEUE_CLEANUP;
        }

        CFRunLoopAddSource(CFRunLoopGetCurrent(), hidDataRef->eventSource, kCFRunLoopDefaultMode);

        ret = (*hidDataRef->hidQueueInterface)->start(hidDataRef->hidQueueInterface);
        if (ret != kIOReturnSuccess)
        {
            boolRet = false;
            goto SETUP_QUEUE_CLEANUP;
        }
    }
    else
    {
        (*hidDataRef->hidQueueInterface)->stop(hidDataRef->hidQueueInterface);
        (*hidDataRef->hidQueueInterface)->dispose(hidDataRef->hidQueueInterface);
        (*hidDataRef->hidQueueInterface)->Release(hidDataRef->hidQueueInterface);
        hidDataRef->hidQueueInterface = NULL;
    }

SETUP_QUEUE_CLEANUP:

    free(keys);
    free(elements);

    return boolRet;
}


//---------------------------------------------------------------------------
// QueueCallbackFunction
//---------------------------------------------------------------------------
void QueueCallbackFunction(
                                  void*              target,
                                  IOReturn             result,
                                  void*              refcon,
                                  void*              sender)
{
    HIDData*          hidDataRef      = (HIDData*)refcon;
    AbsoluteTime     zeroTime     = {0,0};
    CFNumberRef        number        = NULL;
    CFMutableDataRef    element        = NULL;
    HIDElement*    tempHIDElement  = NULL;//(HIDElementRef)refcon;
    IOHIDEventStruct     event;
    bool                change;

    if (!hidDataRef || (sender != hidDataRef->hidQueueInterface))
        return;

    while (result == kIOReturnSuccess)
    {
        result = (*hidDataRef->hidQueueInterface)->getNextEvent(
                                                                hidDataRef->hidQueueInterface,
                                                                &event,
                                                                zeroTime,
                                                                0);

        if (result != kIOReturnSuccess)
            continue;

        // Only intersted in 32 values right now
        if ((event.longValueSize != 0) && (event.longValue != NULL))
        {
            free(event.longValue);
            continue;
        }

        number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &event.elementCookie);
        if (!number)  continue;
        element = (CFMutableDataRef)CFDictionaryGetValue(hidDataRef->hidElementDictionary, number);
        CFRelease(number);

        if (!element ||
            !(tempHIDElement = (HIDElement *)CFDataGetMutableBytePtr(element)))
            continue;

        change = (tempHIDElement->currentValue != event.value);
        tempHIDElement->currentValue = event.value;

        reportHidElementFn(tempHIDElement);
    }

}
