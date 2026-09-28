#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Pre-warps one eye so a simple convex phone-VR lens reconstructs a flatter
// image. The coefficients are user adjustable because viewers differ. A future
// Cardboard SDK bridge can replace these values with its QR-derived mesh.
[[ stitchable ]] half4 maclandCardboardLens(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float strength,
    float chromaticCorrection
) {
    float2 uv = position / size;
    float aspect = size.x / max(size.y, 1.0);
    float2 radial = (uv - 0.5) * 2.0;
    radial.x *= aspect;

    float radiusSquared = dot(radial, radial);
    if (radiusSquared > 1.18) {
        return half4(0.0);
    }

    float k1 = strength;
    float k2 = strength * 0.28;
    float edgeFit = 1.0 / (1.0 + k1 + k2);
    float distortion = (1.0 + k1 * radiusSquared + k2 * radiusSquared * radiusSquared) * edgeFit;

    float2 sampleRadial = radial * distortion;
    sampleRadial.x /= aspect;
    float2 samplePosition = (sampleRadial * 0.5 + 0.5) * size;

    float chroma = chromaticCorrection * radiusSquared;
    float2 redPosition = mix(samplePosition, position, chroma);
    float2 bluePosition = mix(samplePosition, position, -chroma);
    half4 center = layer.sample(samplePosition);
    half red = layer.sample(redPosition).r;
    half blue = layer.sample(bluePosition).b;

    float feather = 1.0 - smoothstep(0.96, 1.18, radiusSquared);
    return half4(red, center.g, blue, center.a) * half(feather);
}
