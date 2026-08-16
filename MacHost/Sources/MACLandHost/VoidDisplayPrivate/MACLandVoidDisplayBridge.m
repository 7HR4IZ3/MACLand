#import "MACLandVoidDisplayBridge.h"
#import "CGVirtualDisplayPrivate.h"

static CGVirtualDisplay *MACLandActiveVoidDisplay;

bool MACLandVoidDisplayRuntimeAvailable(void) {
    return NSClassFromString(@"CGVirtualDisplay") != nil &&
        NSClassFromString(@"CGVirtualDisplayDescriptor") != nil &&
        NSClassFromString(@"CGVirtualDisplaySettings") != nil &&
        NSClassFromString(@"CGVirtualDisplayMode") != nil;
}

bool MACLandVoidDisplayCreate(
    uint32_t width,
    uint32_t height,
    uint32_t serialNumber,
    bool hiDPI,
    const char *name,
    uint32_t *displayID
) {
    if (!MACLandVoidDisplayRuntimeAvailable() ||
        MACLandActiveVoidDisplay != nil ||
        width == 0 ||
        height == 0 ||
        displayID == NULL) {
        return false;
    }

    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    [descriptor setDispatchQueue:dispatch_get_main_queue()];
    descriptor.name = name == NULL
        ? @"MACLand Remote Display"
        : [NSString stringWithUTF8String:name];
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    descriptor.sizeInMillimeters = width >= height
        ? CGSizeMake(121.0, 68.0)
        : CGSizeMake(68.0, 121.0);
    descriptor.serialNum = serialNumber;
    descriptor.vendorID = 0x3456;
    descriptor.productID = 0x1234;

    descriptor.terminationHandler = ^(id _, CGVirtualDisplay *display) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (MACLandActiveVoidDisplay == display) {
                MACLandActiveVoidDisplay = nil;
            }
        });
    };

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (display == nil) {
        return false;
    }

    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc]
        initWithWidth:width
        height:height
        refreshRate:60.0];
    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.modes = @[mode];

    if (![display applySettings:settings] || display.displayID == 0) {
        return false;
    }

    MACLandActiveVoidDisplay = display;
    *displayID = display.displayID;
    return true;
}

void MACLandVoidDisplayDestroy(void) {
    MACLandActiveVoidDisplay = nil;
}

bool MACLandVoidDisplayReconfigure(
    uint32_t width,
    uint32_t height,
    bool hiDPI
) {
    if (MACLandActiveVoidDisplay == nil || width == 0 || height == 0) {
        return false;
    }

    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc]
        initWithWidth:width
        height:height
        refreshRate:60.0];
    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.hiDPI = hiDPI ? 1 : 0;
    settings.modes = @[mode];
    return [MACLandActiveVoidDisplay applySettings:settings];
}
