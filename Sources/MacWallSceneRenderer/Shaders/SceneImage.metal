#include <metal_stdlib>
using namespace metal;

struct SceneImageVertexOutput {
    float4 position [[position]];
    float2 logicalTextureCoordinate;
};

struct SceneImageDrawUniforms {
    float4x4 clipTransform;
    float4 textureCoordinates;
    float4 premultipliedTint;
};

struct SceneMipSamplingUniforms {
    uint4 header;
    float4 contentRects[16];
};

vertex SceneImageVertexOutput sceneImageVertex(
    uint vertexID [[vertex_id]],
    constant SceneImageDrawUniforms &uniforms [[buffer(0)]]
) {
    const float2 localPositions[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    const float2 logicalTextureCoordinates[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };

    SceneImageVertexOutput output;
    output.position = uniforms.clipTransform
        * float4(localPositions[vertexID], 0.0, 1.0);
    output.logicalTextureCoordinate = mix(
        uniforms.textureCoordinates.xy,
        uniforms.textureCoordinates.xy + uniforms.textureCoordinates.zw,
        logicalTextureCoordinates[vertexID]
    );
    return output;
}

float2 sceneMipCoordinate(
    float2 logicalCoordinate,
    float4 contentRect,
    uint2 storageExtent
) {
    float2 halfTexel = 0.5 / float2(storageExtent);
    float2 minimum = contentRect.xy + halfTexel;
    float2 maximum = contentRect.xy + contentRect.zw - halfTexel;
    float2 coordinate = contentRect.xy + logicalCoordinate * contentRect.zw;
    return clamp(coordinate, minimum, maximum);
}

fragment float4 sceneImageFragment(
    SceneImageVertexOutput input [[stage_in]],
    texture2d<float> image [[texture(0)]],
    sampler imageSampler [[sampler(0)]],
    constant SceneImageDrawUniforms &drawUniforms [[buffer(0)]],
    constant SceneMipSamplingUniforms &mipUniforms [[buffer(1)]]
) {
    uint lastLevel = min(
        max(mipUniforms.header.x, 1u) - 1u,
        image.get_num_mip_levels() - 1u
    );
    float2 baseCoordinate = mipUniforms.contentRects[0].xy
        + input.logicalTextureCoordinate * mipUniforms.contentRects[0].zw;
    float lod = clamp(
        image.calculate_clamped_lod(imageSampler, baseCoordinate),
        0.0,
        float(lastLevel)
    );
    uint lowerLevel = uint(floor(lod));
    uint upperLevel = min(lowerLevel + 1u, lastLevel);
    float2 lowerCoordinate = sceneMipCoordinate(
        input.logicalTextureCoordinate,
        mipUniforms.contentRects[lowerLevel],
        uint2(image.get_width(lowerLevel), image.get_height(lowerLevel))
    );
    float2 upperCoordinate = sceneMipCoordinate(
        input.logicalTextureCoordinate,
        mipUniforms.contentRects[upperLevel],
        uint2(image.get_width(upperLevel), image.get_height(upperLevel))
    );
    float4 lower = image.sample(
        imageSampler,
        lowerCoordinate,
        level(float(lowerLevel))
    );
    float4 upper = image.sample(
        imageSampler,
        upperCoordinate,
        level(float(upperLevel))
    );
    float4 sampled = mix(lower, upper, fract(lod));
    float alpha = sampled.a * drawUniforms.premultipliedTint.a;
    return float4(
        sampled.rgb * sampled.a * drawUniforms.premultipliedTint.rgb,
        alpha
    );
}

vertex SceneImageVertexOutput sceneFinalVertex(
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
    output.logicalTextureCoordinate = textureCoordinates[vertexID];
    return output;
}

fragment float4 sceneFinalFragment(
    SceneImageVertexOutput input [[stage_in]],
    texture2d<float> composition [[texture(0)]],
    sampler compositionSampler [[sampler(0)]]
) {
    return composition.sample(compositionSampler, input.logicalTextureCoordinate);
}
