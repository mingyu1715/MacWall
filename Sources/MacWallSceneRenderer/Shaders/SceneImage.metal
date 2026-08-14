#include <metal_stdlib>
using namespace metal;

struct SceneImageVertexOutput {
    float4 position [[position]];
    float2 textureCoordinate;
};

struct SceneImageFragmentUniforms {
    float4 tint;
    float opacity;
};

vertex SceneImageVertexOutput sceneImageVertex(
    uint vertexID [[vertex_id]]
) {
    const float2 positions[4] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, 1.0)
    };
    const float2 textureCoordinates[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    SceneImageVertexOutput output;
    output.position = float4(positions[vertexID], 0.0, 1.0);
    output.textureCoordinate = textureCoordinates[vertexID];
    return output;
}

fragment float4 sceneImageFragment(
    SceneImageVertexOutput input [[stage_in]],
    texture2d<float> image [[texture(0)]],
    sampler imageSampler [[sampler(0)]],
    constant SceneImageFragmentUniforms &uniforms [[buffer(0)]]
) {
    float4 sampled = image.sample(imageSampler, input.textureCoordinate);
    float alpha = sampled.a * uniforms.tint.a * uniforms.opacity;
    return float4(sampled.rgb * uniforms.tint.rgb * alpha, alpha);
}
