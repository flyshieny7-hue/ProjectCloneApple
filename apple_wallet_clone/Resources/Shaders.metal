#include <metal_stdlib>
using namespace metal;

// Liquid Glass Vertex Shader
vertex float4 liquidVertex(uint vertexID [[vertex_id]]) {
    float2 positions[] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

// Liquid Glass Fragment Shader
fragment float4 liquidFragment(
    float4 position [[position]],
    constant float &distortion [[buffer(0)]],
    constant float &time [[buffer(1)]]
) {
    float2 uv = position.xy / float2(1000.0);

    float wave = sin(uv.x * 10.0 + time) * cos(uv.y * 10.0 + time) * distortion;
    float wave2 = sin(uv.x * 20.0 - time * 0.5) * cos(uv.y * 15.0 + time * 0.3) * distortion * 0.5;

    float3 color = float3(0.9, 0.95, 1.0);
    color += wave * 0.1;
    color += wave2 * 0.05;

    float alpha = 0.15 + abs(wave) * 0.3;

    return float4(color, alpha);
}

// Hologram Vertex Shader
vertex float4 hologramVertex(uint vertexID [[vertex_id]]) {
    float2 positions[] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    return float4(positions[vertexID], 0.0, 1.0);
}

// Hologram Fragment Shader
fragment float4 hologramFragment(
    float4 position [[position]],
    constant float &time [[buffer(0)]]
) {
    float2 uv = position.xy / float2(500.0);

    float scanline = sin(uv.y * 200.0 + time * 5.0) * 0.5 + 0.5;
    float hologram = sin(uv.x * 50.0 + time * 2.0) * cos(uv.y * 30.0 - time * 3.0);

    float3 color = float3(0.0, 0.8, 1.0);
    color *= scanline * 0.5 + 0.5;
    color += hologram * 0.2;

    float alpha = 0.3 + scanline * 0.2;

    return float4(color, alpha);
}
