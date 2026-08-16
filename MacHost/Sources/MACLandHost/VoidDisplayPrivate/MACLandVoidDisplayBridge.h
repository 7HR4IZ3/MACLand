#import <stdbool.h>
#import <stdint.h>

bool MACLandVoidDisplayRuntimeAvailable(void);

bool MACLandVoidDisplayCreate(
    uint32_t width,
    uint32_t height,
    uint32_t serialNumber,
    bool hiDPI,
    const char *name,
    uint32_t *displayID
);

void MACLandVoidDisplayDestroy(void);

bool MACLandVoidDisplayReconfigure(
    uint32_t width,
    uint32_t height,
    bool hiDPI
);
