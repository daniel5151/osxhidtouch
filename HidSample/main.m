#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOMessage.h>

#include <ApplicationServices/ApplicationServices.h>
#include <Foundation/Foundation.h>

#include "config.h"
#include "HidUtils.h"

// Swift Code
#include "HidSample-Swift.h"
static Swifty* swift;

//---------------------------------------------------------------------------
// Globals
//---------------------------------------------------------------------------
static IONotificationPortRef gNotifyPort = NULL;
static io_iterator_t         gAddedIter  = 0;
static NSLock*               gLock       = 0;

//---------------------------------------------------------------------------
// TypeDefs
//---------------------------------------------------------------------------

typedef enum {
    UP,
    DOWN,
    NO_CHANGE,
    MOVE,
    RIGHT,
    DOUBLECLICK
} ButtonState;

typedef enum {
    TIPSWITCH,
    PRESS,
    CONTACTID,
    XCOORD,
    YCOORD,
    FINGERCOUNT
} whatInput;

//---------------------------------------------------------------------------
// Simulate Mouse Events
//---------------------------------------------------------------------------

void simulateClick(int x, int y, ButtonState button) {
#if TOUCH_REPORT
    printf("EVENT %d %d %d\n", x, y, button);
#endif
    //static int eventNumber = 0;
    if (button == DOWN) {
        CGEventRef mouse_press = CGEventCreateMouseEvent(NULL,
                                                         kCGEventLeftMouseDown,
                                                         CGPointMake(x, y),
                                                         kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(mouse_press, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, mouse_press);
        CFRelease(mouse_press);
        //eventNumber++;
    }
    else if (button == UP) {
        CGEventRef mouse_release = CGEventCreateMouseEvent(NULL,
                                                           kCGEventLeftMouseUp,
                                                           CGPointMake(x, y),
                                                           kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(mouse_release, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, mouse_release);
        CFRelease(mouse_release);
        //eventNumber++;
    }
    else if (button == RIGHT) {
        CGEventRef mouse_right = CGEventCreateMouseEvent(NULL,
                                                         kCGEventRightMouseDown,
                                                         CGPointMake(x, y),
                                                         kCGMouseButtonRight);
        //CGEventSetIntegerValueField(mouse_press, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, mouse_right);
        CGEventSetType(mouse_right, kCGEventRightMouseUp);
        CGEventPost(kCGHIDEventTap, mouse_right);
        CFRelease(mouse_right);
        //eventNumber++;
    }
    else if (button == DOUBLECLICK)
    {
        CGEventRef mouse_double = CGEventCreateMouseEvent(NULL,
                                                          kCGEventLeftMouseDown,
                                                          CGPointMake(x, y),
                                                          kCGMouseButtonLeft);
        CGEventSetIntegerValueField(mouse_double, kCGMouseEventClickState, 2);
        
        CGEventPost(kCGHIDEventTap, mouse_double);
        CGEventSetType(mouse_double, kCGEventLeftMouseUp);
        CGEventPost(kCGHIDEventTap, mouse_double);
        CGEventSetType(mouse_double, kCGEventLeftMouseDown);
        CGEventPost(kCGHIDEventTap, mouse_double);
        CGEventSetType(mouse_double, kCGEventLeftMouseUp);
        CGEventPost(kCGHIDEventTap, mouse_double);
        CFRelease(mouse_double);
    }
    
    if (button == NO_CHANGE) {
        CGEventRef move = CGEventCreateMouseEvent(NULL,
                                                  kCGEventLeftMouseDragged,
                                                  CGPointMake(x, y),
                                                  kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(move, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);
        //eventNumber++;
    }
    
    if (button == MOVE) {
        CGEventRef move = CGEventCreateMouseEvent(NULL,
                                                  kCGEventMouseMoved,
                                                  CGPointMake(x, y),
                                                  kCGMouseButtonLeft);
        //CGEventSetIntegerValueField(move, kCGMouseEventNumber, eventNumber);
        CGEventPost(kCGHIDEventTap, move);
        CFRelease(move);
        //eventNumber++;
    }
}

//---------------------------------------------------------------------------
// Interpret Events
//---------------------------------------------------------------------------

// Bit of heuristics to maintain position of fingers in last_x and last_y array if
// there are multiple fingers, and the last finger on is not the last finger taken off,
// which usually disrupts the index used for the last_x and last_y array
// This code recalculates the original indexes, stores them in an array

static void recalculateIndex(bool pressed[], short indexFixer[], short allocatedFingers) {
    short temp = 0;
    for (int i = 0; i< allocatedFingers; i++) {
        if (pressed[temp] == 0) {
            temp++;
            while(pressed[temp] == 0 && temp < allocatedFingers)
                temp++;
        }
        if (temp < allocatedFingers)
            indexFixer[i] = temp;
        else {
            indexFixer[i]=-1;
        }
        temp++;
    }
}

static void submitTouch(int fingerId, whatInput type, int input, ButtonState button) {
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
        if (nothingOn) { //sometimes, fingercount is called before timer is, so adjust values
            fingerCount = input;
            allocatedFingers = input;
            nothingOn = 0;
        }
        if (input > allocatedFingers)
            allocatedFingers = input;
        
        if (input > fingerCount && !nothingOn) {
            // The following small loop addresses an issue when a Tipswitch true event isn't generated
            // when fingers are placed. It compares allocated fingers to detected fingers on screen
            for (int i = 0; i < allocatedFingers; i++) {
                if (pressed[i] == 0) {
                    pressed[i] = 1;
                    i = allocatedFingers; //break
                }
            }
            //needs recalculation
            recalculateIndex(pressed, indexFixer, allocatedFingers);
        }
        fingerCount = input;
    }
    else if (type == PRESS)
    {
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
        
        if (button == DOWN) { // dragging: coordinate has to be assigned by now, so safe
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
            if (last_x[fingerId] > 0 && last_y[fingerId] > 0 && holdTime > 7500 && holdNotMoveFar)
                simulateClick(last_x[fingerId], last_y[fingerId], RIGHT);
            
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
        
        //currently unused and broken for multifinger clicking
        /*if (pressed[fingerId] == 1 && button == NO_CHANGE && last_x[fingerId] > 0 && last_y[fingerId] > 0)
         {
         simulateClick(last_x[fingerId], last_y[fingerId], UP);
         
         //simulateClick(last_x[fingerId], last_y[fingerId], DOWN);
         }*/
        
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
        if (abs(last_x[fingerId] - holdStartCoord[0]) > 10 || abs(last_y[fingerId] - holdStartCoord[1]) > 10) {
            holdNotMoveFar = false;
        }
        /*for (int i = 0; i < NUM_TOUCHES; i++) //debug
         {
         printf("%4d,%4d", last_x[i], last_y[i]);
         if (i+1 < NUM_TOUCHES)
         printf("||");
         else
         printf("\n");
         }*/
    }
    
    if (!nothingOn)
    {
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
    //printf("type: %d, Holdnotmovefar: %d, holdtime: %d, allocatedfingers %d, fingercount %d, missingfingerschecked: %d, nothingon: %d\n", type, holdNotMoveFar, holdTime, allocatedFingers, fingerCount, missingFingersChecked, nothingOn);
    
    //printf("%d, %d, %d, %d, %d, %d, %d, %d, %d, %d\n", indexFixer[0], indexFixer[1], indexFixer[2], indexFixer[3], indexFixer[4], indexFixer[5], indexFixer[6], indexFixer[7], indexFixer[8], indexFixer[9]);
    
}

//---------------------------------------------------------------------------
// Interpret HID events
//---------------------------------------------------------------------------

static void reportHidElement(HIDElement *element) {
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

//---------------------------------------------------------------------------
// Methods
//---------------------------------------------------------------------------
static void InitHIDNotifications(SInt32, SInt32);
static void HIDDeviceAdded(void* refCon, io_iterator_t iterator);
static void DeviceNotification(
    void*        refCon, 
    io_service_t service, 
    natural_t    messageType, 
    void*        messageArgument
);
static bool FindHIDElements(HIDData* hidDataRef);
static bool SetupQueue(HIDData* hidDataRef);
static void QueueCallbackFunction(void* target,IOReturn result,void* refcon,void* sender);

int main (int argc, const char*  argv[]) {
    // Setup Swift Bridge
    swift = [[Swifty alloc] init];
    
    gLock = [[NSLock alloc] init];
    InitHIDNotifications(TOUCH_VID, TOUCH_PID);

    printf("To keep driver running keep this window in the background...\n\n");
    
    CFRunLoopRun();
    
    return 0;
}


//---------------------------------------------------------------------------
// InitHIDNotifications
//
// This routine just creates our master port for IOKit and turns around
// and calls the routine that will alert us when a HID Device is plugged in.
//---------------------------------------------------------------------------

static void InitHIDNotifications(SInt32 vendorID, SInt32 productID)
{
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

static void HIDDeviceAdded(void* refCon, io_iterator_t iterator)
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
            
            
            
#if TOUCH_REPORT
            printf("Please touch screen to continue.\n\n");
#endif
            
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

static void DeviceNotification(void*         refCon,
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

static bool acceptHidElement(HIDElement *element) {
    printHidElement("acceptHidElement", element);
    
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

static bool FindHIDElements(HIDData* hidDataRef)
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
        
        newElement.owner = hidDataRef;
        
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
static bool SetupQueue(HIDData* hidDataRef)
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
        
        printHidElement("SetupQueue", tempHIDElement);
        
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
static void QueueCallbackFunction(
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
        
        reportHidElement(tempHIDElement);
    }
    
}

