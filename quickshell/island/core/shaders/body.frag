#version 440
// The island's body: one fragment shader draws the whole silhouette (rounded
// pill, or flush with the top edge with concave flares) as a signed distance
// field and fills it with a flat colour. Far cheaper per frame than tessellating
// a path and clipping the content through an offscreen pass, which matters on
// a 144 Hz display.
//
// Rebuild with scripts/build-shaders.sh after editing.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // item size in px
    vec4 shape;     // x: left edge of the body, y: body width, z: body height, w: bottom corner radius
    vec4 shape2;    // x: top corner radius, y: flare radius, z: unused, w: unused
    vec4 tint;      // rgb: fill colour, a: opacity
    vec4 glow;      // rgb: pulse colour, a: pulse strength (0 = off)
} ubuf;

float boxSdf(vec2 p, vec2 b) {
    vec2 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

float shapeSdf(vec2 p) {
    float ox = ubuf.shape.x;
    float W = ubuf.shape.y;
    float H = ubuf.shape.z;
    float rb = ubuf.shape.w;
    float rt = ubuf.shape2.x;
    float f = ubuf.shape2.y;

    // body: top half uses the top radius, bottom half the bottom radius
    vec2 q = p - vec2(ox + 0.5 * W, 0.5 * H);
    float r = q.y < 0.0 ? rt : rb;
    vec2 d2 = abs(q) - vec2(0.5 * W, 0.5 * H) + r;
    float d = min(max(d2.x, d2.y), 0.0) + length(max(d2, 0.0)) - r;

    // flares: the corner square beside the body minus a disc, mirrored left/right
    if (f > 0.5) {
        vec2 pm = vec2(abs(q.x), p.y);
        float sq = boxSdf(pm - vec2(0.5 * W + 0.5 * f, 0.5 * f), vec2(0.5 * f));
        float disc = length(pm - vec2(0.5 * W + f, f)) - f;
        d = min(d, max(sq, -disc));
    }
    return d;
}

void main() {
    float d = shapeSdf(qt_TexCoord0 * ubuf.size);
    float cover = clamp(0.5 - d, 0.0, 1.0);          // 1 px anti-aliased edge
    float a = ubuf.tint.a * cover;
    vec3 rgb = ubuf.tint.rgb * a;                     // premultiplied
    // Pulse: a 2.5 px ring just inside the outline plus a soft inner glow.
    if (ubuf.glow.a > 0.002) {
        float ring = clamp(1.0 - abs(d + 1.5) / 1.5, 0.0, 1.0);
        float inner = 0.45 * exp(min(d, 0.0) / 6.0);
        float g = ubuf.glow.a * max(ring, inner) * cover;
        rgb = rgb * (1.0 - g) + ubuf.glow.rgb * g;
        a = a * (1.0 - g) + g;
    }
    fragColor = vec4(rgb, a) * ubuf.qt_Opacity;
}
