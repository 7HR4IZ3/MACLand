#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN
/// The optional SDK is linked by scripts/setup-cardboard.sh. Unconfigured builds
/// retain a working, explicitly uncalibrated stereo preview.
@interface MACLandCardboard : NSObject
@property(nonatomic, readonly) BOOL available;
@property(nonatomic, readonly) BOOL hasProfile;
- (void)scan;
- (BOOL)configureWithDevice:(id<MTLDevice>)device width:(int)width height:(int)height NS_SWIFT_NAME(configure(with:width:height:));
- (matrix_float4x4)projectionForEye:(int)eye NS_SWIFT_NAME(projection(eye:));
- (matrix_float4x4)eyeFromHead:(int)eye NS_SWIFT_NAME(eyeFromHead(_:));
- (void)distortWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                  texture:(id<MTLTexture>)texture width:(int)width height:(int)height NS_SWIFT_NAME(distort(with:texture:width:height:));
@end
NS_ASSUME_NONNULL_END
