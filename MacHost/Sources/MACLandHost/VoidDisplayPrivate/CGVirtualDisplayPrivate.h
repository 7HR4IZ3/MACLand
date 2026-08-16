/*
 This declaration is adapted from the open-source VoidDisplay project at the
 pinned source commit 1169fcd2e51103746976b2b2cd27c112f3e13082:
 https://github.com/iamsyc/VoidDisplay

 VoidDisplay is Apache-2.0 licensed. MACLand changed this file by reducing the
 declaration surface to the runtime types used by its own bridge. The
 declarations below describe the private macOS CGVirtualDisplay runtime used
 by that project. They are kept behind MACLandVoidDisplayBridge rather than
 exposed to the rest of MACLand.
 */

#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplayDescriptor;

@interface CGVirtualDisplayMode : NSObject

- (instancetype)initWithWidth:(NSUInteger)width
                        height:(NSUInteger)height
                  refreshRate:(CGFloat)refreshRate;

@end

@interface CGVirtualDisplaySettings : NSObject

@property(nonatomic) unsigned int hiDPI;
@property(retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;

- (instancetype)init;

@end

@interface CGVirtualDisplay : NSObject

@property(readonly, nonatomic) CGDirectDisplayID displayID;

- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;

@end

@interface CGVirtualDisplayDescriptor : NSObject

@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) unsigned int maxPixelsHigh;
@property(nonatomic) unsigned int maxPixelsWide;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int serialNum;
@property(nonatomic) unsigned int productID;
@property(nonatomic) unsigned int vendorID;
@property(copy, nonatomic) void (^terminationHandler)(id, CGVirtualDisplay *);

- (instancetype)init;
- (void)setDispatchQueue:(dispatch_queue_t)queue;

@end

NS_ASSUME_NONNULL_END
