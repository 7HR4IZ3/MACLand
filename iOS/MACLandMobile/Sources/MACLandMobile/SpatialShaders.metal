#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]]; float2 uv; };
struct Uniforms {
    float4x4 eyeToWorld;
    float4x4 inverseProjection;
    float4 reticle; // xyz world position, dwell progress
    float4 state;   // surface count, active surface index, video available, input armed
};
struct Surface { float4 center; float4 size; float4 atlas; };
vertex VertexOut spatialVertex(uint id [[vertex_id]]) {
    const float2 points[] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    VertexOut result;
    result.position = float4(points[id],0,1);
    result.uv = points[id] * 0.5 + 0.5;
    return result;
}
fragment float4 spatialFragment(VertexOut in [[stage_in]],
                                 constant Uniforms &u [[buffer(0)]],
                                 constant Surface *surfaces [[buffer(1)]],
                                 texture2d<float> video [[texture(0)]],
                                 texture2d<float> atlas [[texture(1)]]) {
    constexpr sampler sampleFilter(coord::normalized, address::clamp_to_edge, filter::linear);
    // Cardboard projection uses OpenGL clip coordinates; only the ray is used.
    float4 p = u.inverseProjection * float4(in.uv * 2 - 1, -1, 1);
    float3 origin = u.eyeToWorld[3].xyz;
    float3 ray = normalize((u.eyeToWorld * float4(p.xyz / p.w, 0)).xyz);
    float horizon = exp(-abs(ray.y + 0.18) * 5);
    float3 color = mix(float3(0.018,0.033,0.075), float3(0.19,0.28,0.41), horizon);
    // Reflect the night sky in a quiet lake below the floating workspace.
    if (ray.y < -0.12) {
        float ripple = sin(ray.x * 120 + ray.y * 220) * sin(ray.y * 90) * 0.012;
        color += float3(0.035,0.055,0.08) + ripple;
    } else {
        float stars = fract(sin(dot(floor(ray.xy * 650), float2(127.1,311.7))) * 43758.5453);
        color += step(0.9985, stars) * smoothstep(0.05,0.4,ray.y) * 0.35;
    }
    float nearest = 1e8;
    int selected = -1;
    float2 uv = 0;
    if (abs(ray.z) > 0.00001) {
        for (int i = 0; i < int(u.state.x); ++i) {
            Surface surface = surfaces[i];
            float t = (surface.center.z - origin.z) / ray.z;
            float horizontal;
            float radius = surface.size.w;
            if (radius > 0) {
                float2 offset = float2(origin.x - surface.center.x, origin.z - surface.center.z - radius);
                float2 direction = ray.xz;
                float a = dot(direction,direction);
                float b = 2 * dot(offset,direction);
                float c = dot(offset,offset) - radius * radius;
                float discriminant = b*b - 4*a*c;
                if (a <= 0 || discriminant < 0) continue;
                float nearT = (-b - sqrt(discriminant))/(2*a);
                float farT = (-b + sqrt(discriminant))/(2*a);
                t = nearT > 0 && origin.z + nearT*ray.z <= surface.center.z + radius ? nearT : farT;
                if (t <= 0 || origin.z + t*ray.z > surface.center.z + radius) continue;
                float3 hit = origin + ray*t;
                horizontal = atan2(hit.x - surface.center.x, surface.center.z + radius - hit.z)*radius;
            } else {
                horizontal = origin.x + t*ray.x - surface.center.x;
            }
            float3 hit = origin + ray*t;
            float2 local = float2(0.5 + horizontal/surface.size.x,
                                 0.5 - (hit.y - surface.center.y)/surface.size.y);
            if (t > 0 && t < nearest && all(local >= 0) && all(local <= 1)) {
                if (surface.size.z < 0.5) {
                    float alpha = atlas.sample(sampleFilter, surface.atlas.xy + local * surface.atlas.zw).a;
                    if (alpha < 0.02) continue;
                } else {
                    float2 q = abs(local - 0.5)*surface.size.xy - surface.size.xy*0.5 + 0.035;
                    if (length(max(q,0.0)) + min(max(q.x,q.y),0.0) > 0.035) continue;
                }
                selected = i; nearest = t; uv = local;
            }
        }
    }
    if (selected >= 0) {
        Surface surface = surfaces[selected];
        bool display = surface.size.z > 0.5;
        if (display && u.state.z > 0.5) {
            color = video.sample(sampleFilter, uv).rgb;
        } else {
            float2 atlasUV = surface.atlas.xy + uv * surface.atlas.zw;
            float4 glass = atlas.sample(sampleFilter, atlasUV);
            color = mix(color, glass.rgb, glass.a);
        }
        float edge = min(min(uv.x,1-uv.x)*surface.size.x, min(uv.y,1-uv.y)*surface.size.y);
        if (edge < 0.004) color = selected == int(u.state.y) ? float3(0.16,0.76,1) : float3(0.21,0.26,0.32);
        if (selected == int(u.state.y) && !display) color += float3(0.035,0.065,0.065);
    }
    // A world-space reticle converges at the actual target depth in both eyes.
    float t = (u.reticle.z - origin.z) / ray.z;
    if (t > 0 && abs(ray.z) > 0.00001) {
        float2 delta = (origin + t * ray - u.reticle.xyz).xy;
        float radius = 0.008 * length(u.reticle.xyz);
        float r = length(delta);
        float angle = fract(atan2(delta.x, delta.y) / (2 * M_PI_F) + 1);
        if (r < radius * 0.19) color = float3(1);
        if (r > radius * 0.78 && r < radius) {
            color = angle < u.reticle.w ? float3(0.16,0.76,1) : float3(0.65);
        }
    }
    return float4(color, 1);
}
