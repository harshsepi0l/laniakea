import Metal

/// Atlas's map shaders, compiled by the app the first time a map appears (and kept), so building
/// the app needs no Metal toolchain.
enum GraphShaders {
    /// The compiled library, shared by every map.
    static func library(device: MTLDevice) -> MTLLibrary? {
        if let cached, cached.device === device { return cached }
        let library = try? device.makeLibrary(source: source, options: nil)
        cached = library
        return library
    }

    private static var cached: MTLLibrary?

    private static let source = #"""
#include <metal_stdlib>
using namespace metal;

// Atlas's map on the GPU. Everything is uploaded once in layout coordinates; moving the camera
// only changes `worldToClip`, so panning and zooming cost the same with ten objects or ten
// thousand. Sizes are in points, as in the SwiftUI drawing this replaces, so dots, rings and lines
// keep their size on screen whatever the zoom.
//
// The structs below must match their Swift twins in GraphRenderer.swift field for field.

struct Uniforms {
    float4x4 worldToClip;
    float2 viewport;          // drawable size in pixels
    float pixelsPerPoint;
    float zoom;
    float detailThreshold;    // node size below which dots draw faint
};

struct Sprite {
    float4 color;             // straight alpha
    float3 position;
    float size;               // node size 0...1, which sets the dot radius
    float shape;              // 0 disc, 1 glow, 2 ring
    float extra;              // glow: multiple of the dot radius; ring: points outside the dot
    float width;              // ring line width in points
    float faintable;          // 1: fades when smaller than the detail threshold
};

struct Segment {
    float4 color;
    float3 a;
    float3 b;
    float width;              // points
    float soft;               // 1: a soft glow that fades across its width
};

struct RegionQuad {
    float4 color;
    float4 corners[4];        // top left, top right, bottom left, bottom right
};

/// The dot radius in points: small for most objects so thousands stay legible, growing a little
/// as you zoom in.
static float dotRadius(float size, float zoom) {
    return (0.7 + 4.6 * pow(size, 1.6)) * min(pow(zoom, 0.35), 3.0);
}

// MARK: Sprites (dots, glows, rings)

struct SpriteOut {
    float4 position [[position]];
    float4 color;
    float2 local;                     // pixels from the centre
    float radius [[flat]];            // pixels
    float ringInner [[flat]];
    float ringOuter [[flat]];
    float shape [[flat]];
};

vertex SpriteOut spriteVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                              constant Sprite *sprites [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
    Sprite s = sprites[iid];
    float dot = dotRadius(s.size, u.zoom);
    float radius = dot, inner = 0, outer = 0;
    if (s.shape == 1) {
        radius = dot * s.extra;
    } else if (s.shape == 2) {
        float r = dot + s.extra;
        inner = r - s.width * 0.5;
        outer = r + s.width * 0.5;
        radius = outer;
    }
    float ppp = u.pixelsPerPoint;
    // One extra pixel all round for antialiasing.
    float extent = radius * ppp + 1.0;
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    float4 centre = u.worldToClip * float4(s.position, 1.0);

    SpriteOut out;
    out.position = centre + float4(corner * extent * 2.0 / u.viewport * centre.w, 0, 0);
    float4 c = s.color;
    if (s.faintable > 0.5 && s.size < u.detailThreshold) { c.a *= 0.6; }
    out.color = c;
    out.local = corner * extent;
    out.radius = radius * ppp;
    out.ringInner = inner * ppp;
    out.ringOuter = outer * ppp;
    out.shape = s.shape;
    return out;
}

fragment float4 spriteFragment(SpriteOut in [[stage_in]]) {
    float d = length(in.local);
    float a;
    if (in.shape == 1) {
        // Fades linearly to clear at the edge, like the radial gradient it replaces.
        a = saturate(1.0 - d / in.radius);
    } else if (in.shape == 2) {
        a = saturate(d - in.ringInner + 0.5) * saturate(in.ringOuter - d + 0.5);
    } else {
        a = saturate(in.radius - d + 0.5);
    }
    float alpha = in.color.a * a;
    return float4(in.color.rgb * alpha, alpha);
}

// MARK: Segments (links, Laniakea's edge)

struct SegmentOut {
    float4 position [[position]];
    float4 color;
    float across;                     // pixels from the centre line
    float halfWidth [[flat]];
    float soft [[flat]];
};

vertex SegmentOut segmentVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                constant Segment *segments [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]]) {
    Segment s = segments[iid];
    float4 ca = u.worldToClip * float4(s.a, 1.0);
    float4 cb = u.worldToClip * float4(s.b, 1.0);
    float2 half_viewport = u.viewport * 0.5;
    float2 pa = ca.xy / ca.w * half_viewport;
    float2 pb = cb.xy / cb.w * half_viewport;
    float2 dir = pb - pa;
    float len = length(dir);
    dir = len > 1e-4 ? dir / len : float2(1, 0);
    float2 normal = float2(-dir.y, dir.x);

    float halfWidth = s.width * 0.5 * u.pixelsPerPoint;
    float extent = s.soft > 0.5 ? halfWidth : halfWidth + 1.0;
    float side = (vid & 1) ? 1.0 : -1.0;
    bool atB = (vid & 2) != 0;
    // Crisp lines get square caps, so the short pieces of an outline meet without notches; soft
    // glows stop at their ends, or the overlaps would double up at every joint.
    float cap = s.soft > 0.5 ? 0.0 : extent;
    float2 p = (atB ? pb + dir * cap : pa - dir * cap) + normal * side * extent;

    SegmentOut out;
    out.position = float4(p / half_viewport, 0, 1);
    out.color = s.color;
    out.across = side * extent;
    out.halfWidth = halfWidth;
    out.soft = s.soft;
    return out;
}

fragment float4 segmentFragment(SegmentOut in [[stage_in]]) {
    float d = abs(in.across);
    float a;
    if (in.soft > 0.5) {
        float t = saturate(1.0 - d / in.halfWidth);
        a = t * t;
    } else {
        a = saturate(in.halfWidth - d + 0.5);
    }
    float alpha = in.color.a * a;
    return float4(in.color.rgb * alpha, alpha);
}

// MARK: Region (Laniakea's soft fill, pre-blurred into a texture)

struct RegionOut {
    float4 position [[position]];
    float2 uv;
};

vertex RegionOut regionVertex(uint vid [[vertex_id]],
                              constant RegionQuad &quad [[buffer(0)]],
                              constant Uniforms &u [[buffer(1)]]) {
    RegionOut out;
    out.position = u.worldToClip * quad.corners[vid];
    out.uv = float2((vid & 1) ? 1.0 : 0.0, (vid & 2) ? 1.0 : 0.0);
    return out;
}

fragment float4 regionFragment(RegionOut in [[stage_in]],
                               constant RegionQuad &quad [[buffer(0)]],
                               texture2d<float> mask [[texture(0)]]) {
    constexpr sampler linear(filter::linear, address::clamp_to_edge);
    float alpha = quad.color.a * mask.sample(linear, in.uv).a;
    return float4(quad.color.rgb * alpha, alpha);
}
"""#
}
