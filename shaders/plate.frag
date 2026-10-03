#version 460 core

// Plate compositor — the runtime half of docs/PLATES.md, pixel-for-pixel the
// maths of tools/plates/composite.py:
//
//   out.rgb = C.rgb·C.a + T(uv) · D · tint      (premultiplied)
//   out.a   = C.a
//
// The hi/lo UV bytes must never be filtered (bilinear between (1,255) and
// (2,0) is garbage), so uUv/uUv2 are bound with FilterQuality.none and
// filtered here by hand: fetch the 4 surrounding texels, rebuild their UVs
// and D, interpolate those, then sample the art once at screen resolution.

#include <flutter/runtime_effect.glsl>

precision highp float;

// Float uniforms, in FragmentShader.setFloat order (see plate_shader.dart).
uniform vec2 uDestSize;     // 0, 1   destination rect size, canvas px
uniform vec2 uDestOffset;   // 2, 3   destination rect top-left, canvas px
uniform vec2 uPlateSize;    // 4, 5   plate image size, plate px
uniform vec3 uTint;         // 6, 7, 8  colour of the label light
uniform float uArtEnabled;  // 9      1 = composite the art, 0 = colour only

// Samplers, in setImageSampler order.
uniform sampler2D uColor;   // 0  beauty, premultiplied   FilterQuality.low
uniform sampler2D uUv;      // 1  U hi, V hi, D           FilterQuality.none
uniform sampler2D uUv2;     // 2  U lo, V lo              FilterQuality.none
uniform sampler2D uArt;     // 3  label atlas             FilterQuality.low

out vec4 fragColor;

// One data texel at integer plate coordinates t: xy = atlas UV, z = D.
vec3 texelData(vec2 t) {
  vec2 c = (t + 0.5) / uPlateSize;
  vec3 hi = floor(texture(uUv, c).rgb * 255.0 + 0.5);
  vec2 lo = floor(texture(uUv2, c).rg * 255.0 + 0.5);
  return vec3((hi.xy * 256.0 + lo) / 65535.0, hi.z / 255.0);
}

void main() {
  vec2 local = (FlutterFragCoord().xy - uDestOffset) / uDestSize;
  vec4 c = texture(uColor, local);
  if (uArtEnabled < 0.5) {
    fragColor = c;
    return;
  }

  vec2 p = local * uPlateSize - 0.5;
  vec2 i0 = floor(p);
  vec2 f = p - i0;
  vec2 hiT = uPlateSize - 1.0;
  vec2 a = clamp(i0, vec2(0.0), hiT);
  vec2 b = clamp(i0 + 1.0, vec2(0.0), hiT);
  vec3 d00 = texelData(a);
  vec3 d10 = texelData(vec2(b.x, a.y));
  vec3 d01 = texelData(vec2(a.x, b.y));
  vec3 d11 = texelData(b);
  vec3 d = mix(mix(d00, d10, f.x), mix(d01, d11, f.x), f.y);
  if (d.z <= 0.0) {
    fragColor = c;
    return;
  }
  vec3 art = texture(uArt, d.xy).rgb;
  fragColor = vec4(c.rgb + art * d.z * uTint, c.a);
}
