#import "MACLandCardboard.h"
#if MACLAND_CARDBOARD
#include "cardboard.h"
#endif

@implementation MACLandCardboard {
#if MACLAND_CARDBOARD
    CardboardLensDistortion *_lens;
    CardboardDistortionRenderer *_renderer;
#endif
}
- (BOOL)available {
#if MACLAND_CARDBOARD
    return YES;
#else
    return NO;
#endif
}
- (BOOL)hasProfile {
#if MACLAND_CARDBOARD
    uint8_t *params = nullptr;
    int size = 0;
    CardboardQrCode_getSavedDeviceParams(&params, &size);
    if (params) CardboardQrCode_destroy(params);
    return size > 0;
#else
    return NO;
#endif
}
- (void)scan {
#if MACLAND_CARDBOARD
    CardboardQrCode_scanQrCodeAndSaveDeviceParams();
#endif
}
- (BOOL)configureWithDevice:(id<MTLDevice>)device width:(int)width height:(int)height {
#if MACLAND_CARDBOARD
    if (_renderer) { CardboardDistortionRenderer_destroy(_renderer); _renderer = nullptr; }
    if (_lens) { CardboardLensDistortion_destroy(_lens); _lens = nullptr; }
    uint8_t *params = nullptr;
    int size = 0;
    CardboardQrCode_getSavedDeviceParams(&params, &size);
    if (!params || size <= 0) return NO;
    _lens = CardboardLensDistortion_create(params, size, width, height);
    CardboardQrCode_destroy(params);
    if (!_lens) return NO;
    CardboardMetalDistortionRendererConfig config = {};
    config.mtl_device = (uint64_t)(__bridge void *)device;
    config.color_attachment_pixel_format = MTLPixelFormatBGRA8Unorm;
    _renderer = CardboardMetalDistortionRenderer_create(&config);
    if (!_renderer) return NO;
    for (int eye = 0; eye < 2; ++eye) {
        CardboardMesh mesh;
        CardboardLensDistortion_getDistortionMesh(_lens, (CardboardEye)eye, &mesh);
        CardboardDistortionRenderer_setMesh(_renderer, &mesh, (CardboardEye)eye);
    }
    return YES;
#else
    return NO;
#endif
}
- (matrix_float4x4)projectionForEye:(int)eye {
    matrix_float4x4 matrix = matrix_identity_float4x4;
#if MACLAND_CARDBOARD
    if (_lens) CardboardLensDistortion_getProjectionMatrix(_lens, (CardboardEye)eye, 0.05, 100, (float *)&matrix);
#endif
    return matrix;
}
- (matrix_float4x4)eyeFromHead:(int)eye {
    matrix_float4x4 matrix = matrix_identity_float4x4;
#if MACLAND_CARDBOARD
    if (_lens) CardboardLensDistortion_getEyeFromHeadMatrix(_lens, (CardboardEye)eye, (float *)&matrix);
#endif
    return matrix;
}
- (void)distortWithEncoder:(id<MTLRenderCommandEncoder>)encoder
                  texture:(id<MTLTexture>)texture width:(int)width height:(int)height {
#if MACLAND_CARDBOARD
    if (!_renderer) return;
    CardboardMetalDistortionRendererTargetConfig target = {};
    target.render_command_encoder = (uint64_t)(__bridge void *)encoder;
    target.screen_width = width;
    target.screen_height = height;
    CardboardEyeTextureDescription left = {(uint64_t)(__bridge void *)texture, 0, 0.5, 1, 0};
    CardboardEyeTextureDescription right = {(uint64_t)(__bridge void *)texture, 0.5, 1, 1, 0};
    CardboardDistortionRenderer_renderEyeToDisplay(_renderer, (uint64_t)&target,
                                                  0, 0, width, height, &left, &right);
#endif
}
- (void)dealloc {
#if MACLAND_CARDBOARD
    if (_renderer) CardboardDistortionRenderer_destroy(_renderer);
    if (_lens) CardboardLensDistortion_destroy(_lens);
#endif
}
@end
