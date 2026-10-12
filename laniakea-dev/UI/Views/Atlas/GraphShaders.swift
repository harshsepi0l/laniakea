import Metal

/// The map shaders for Atlas and the sky view, compiled by the app the first time either appears
/// (and kept), so building the app needs no Metal toolchain.
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
    float time;               // years from now
    float perspective;        // camera distance in layout units; 0 looking straight down
    float expansion;          // the region's growth per year about expansionOrigin
    float3 expansionOrigin;   // the Milky Way, relative to the fit centre
};

struct Sprite {
    float4 color;             // straight alpha
    float3 position;
    float3 velocity;          // layout units per year
    float size;               // node size 0...1, which sets the dot radius
    float shape;              // 0 disc, 1 glow, 2 ring, 3 glow sized in layout units, 4 black hole
    float extra;              // glow: multiple of the dot radius; ring: points outside the dot;
                              // shape 3: radius in layout units
    float width;              // ring line width in points
    float faintable;          // 1: fades when smaller than the detail threshold
};

struct Segment {
    float4 color;
    float3 a;
    float3 b;
    float3 velocityA;
    float3 velocityB;
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
                              constant Uniforms &u [[buffer(1)]],
                              constant float &opacity [[buffer(2)]]) {
    Sprite s = sprites[iid];
    float dot = dotRadius(s.size, u.zoom);
    float radius = dot, inner = 0, outer = 0;
    if (s.shape == 1 || s.shape == 4) {
        radius = dot * s.extra;
    } else if (s.shape == 2) {
        float r = dot + s.extra;
        inner = r - s.width * 0.5;
        outer = r + s.width * 0.5;
        radius = outer;
    }
    float ppp = u.pixelsPerPoint;
    float3 here = s.position + s.velocity * u.time;
    float4 centre = u.worldToClip * float4(here, 1.0);
    SpriteOut out;
    if (centre.w <= 0.0 || (u.perspective > 0.0 && centre.w < u.perspective * 0.08)) {
        // Behind the camera, or so close it would fill the screen.
        out.position = float4(2, 2, 0, 1);
        out.color = float4(0);
        out.local = float2(0);
        out.radius = 0; out.ringInner = 0; out.ringOuter = 0; out.shape = 0;
        return out;
    }
    float shape = s.shape;
    if (shape == 3 && centre.w > 0.0) {
        // A glow as big as a region of space: measure its radius on screen along each axis.
        float2 half_viewport = u.viewport * 0.5;
        float2 c0 = centre.xy / centre.w * half_viewport;
        float r = 0;
        for (int axis = 0; axis < 3; axis++) {
            float3 offset = float3(0);
            offset[axis] = s.extra;
            float4 c = u.worldToClip * float4(here + offset, 1.0);
            if (c.w > 0.0) { r = max(r, length(c.xy / c.w * half_viewport - c0)); }
        }
        radius = min(r, 600.0) / ppp;
        shape = 1;
    } else if (u.perspective > 0.0) {
        // Nearer objects draw a little bigger in 3D.
        float nearness = clamp(u.perspective / centre.w, 0.6, 1.8);
        radius *= nearness; inner *= nearness; outer *= nearness;
    }
    // One extra pixel all round for antialiasing.
    float extent = radius * ppp + 1.0;
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);

    out.position = centre + float4(corner * extent * 2.0 / u.viewport * centre.w, 0, 0);
    float4 c = s.color;
    c.a *= opacity;
    if (s.faintable > 0.5 && s.size < u.detailThreshold) { c.a *= 0.6; }
    out.color = c;
    out.local = corner * extent;
    out.radius = radius * ppp;
    out.ringInner = inner * ppp;
    out.ringOuter = outer * ppp;
    out.shape = shape;
    return out;
}

fragment float4 spriteFragment(SpriteOut in [[stage_in]]) {
    float d = length(in.local);
    float a;
    if (in.shape == 4) {
        // A black hole: a black disc inside a thin bright photon ring, with white squiggles
        // spiralling in from around it and fading outward.
        float core = in.radius * 0.38;
        float o = in.color.a;
        if (d < core - 0.75) { return float4(0, 0, 0, o); }
        float ring = saturate(1.0 - abs(d - core) / 1.4);
        float t = saturate((d - core) / (in.radius - core));
        float angle = atan2(in.local.y, in.local.x);
        // Three arms winding inward on a log spiral, drawn as thin lines.
        float phase = 3.0 * angle + 7.0 * log(max(d, 1.0) / core);
        // Plain products, not pow(): fast-math pow(0, y) gives NaN, which hid the swirls.
        float arm = saturate(1.0 - abs(sin(phase)) * 1.5);
        float fade = 1.0 - t;
        float swirl = arm * arm * fade * 1.1;
        float white = max(ring, swirl) * o;
        // Black behind the swirl, so it reads on light backgrounds too.
        float body = (d < core + 1.0 ? 1.0 : 0.0) * o;
        float alpha = max(white, body);
        return float4(float3(white), alpha);
    }
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
                                constant Uniforms &u [[buffer(1)]],
                                constant float &opacity [[buffer(2)]]) {
    Segment s = segments[iid];
    float4 ca = u.worldToClip * float4(s.a + s.velocityA * u.time, 1.0);
    float4 cb = u.worldToClip * float4(s.b + s.velocityB * u.time, 1.0);
    float near = u.perspective * 0.08;
    if (ca.w <= near || cb.w <= near) {
        // An end behind the camera, or so close it would streak across the screen: skip it.
        SegmentOut gone;
        gone.position = float4(2, 2, 0, 1);
        gone.color = float4(0); gone.across = 0; gone.halfWidth = 1; gone.soft = 0;
        return gone;
    }
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
    out.color.a *= opacity;
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
    float4 corner = quad.corners[vid];
    // The region grows with the expansion of space, about the Milky Way.
    corner.xyz += (corner.xyz - u.expansionOrigin) * u.expansion * u.time;
    out.position = u.worldToClip * corner;
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

// MARK: Sky view stars

// The naked-eye stars over the camera. Each star's J2000 direction is uploaded once; one matrix a
// frame turns them to the local sky and into the camera's view, and a pinhole projection with
// the camera's focal length puts them on screen.

struct SkyUniforms {
    float4x4 j2000ToView;     // rows: screen right, screen up, the way the camera looks
    float2 viewport;          // drawable size in pixels
    float2 screen;            // drawable size in points
    float pixelsPerPoint;
    float focal;              // points, zoom included
};

struct SkyStar {
    float4 color;
    float3 direction;         // J2000 unit vector
    float radius;             // points
};

struct SkyStarOut {
    float4 position [[position]];
    float4 color;
    float2 local;
    float radius [[flat]];
};

vertex SkyStarOut skyStarVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                constant SkyStar *stars [[buffer(0)]],
                                constant SkyUniforms &u [[buffer(1)]]) {
    SkyStar s = stars[iid];
    float3 v = (u.j2000ToView * float4(s.direction, 0)).xyz;
    SkyStarOut out;
    out.color = s.color;
    out.radius = s.radius * u.pixelsPerPoint;
    if (v.z < 0.05) {
        // Behind the camera: collapse to nothing.
        out.position = float4(2, 2, 0, 1);
        out.local = float2(0);
        return out;
    }
    float2 points = v.xy / v.z * u.focal;
    float extent = out.radius + 1.0;
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    out.position = float4(points * 2.0 / u.screen + corner * extent * 2.0 / u.viewport, 0, 1);
    out.local = corner * extent;
    return out;
}

fragment float4 skyStarFragment(SkyStarOut in [[stage_in]]) {
    float a = saturate(in.radius - length(in.local) + 0.5) * in.color.a;
    return float4(in.color.rgb * a, a);
}
"""#
}
