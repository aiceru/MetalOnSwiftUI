//
//  Shaders.metal
//  MetalOnSwiftUI
//
//  Created by Wooseok Son on 2021/10/06.
//

#include <metal_stdlib>
using namespace metal;

struct ColoredVertex {
    float4 position [[ position ]];
    float4 color;
};

vertex ColoredVertex basic_vertex(const device packed_float2* frameSize [[ buffer(0) ]],
                                  const device packed_float2* pos [[ buffer(1) ]],
                                  const device packed_float4* color_array [[ buffer(2) ]],
                                  unsigned int vid [[ vertex_id ]]) {
    ColoredVertex vert;
    float wScale = frameSize[0].x / 2.0;
    float hScale = frameSize[0].y / 2.0;
    float2 center = float2( (pos[0].x - wScale) / wScale, (pos[0].y - hScale) / (0 - hScale) );
    switch (vid % 4) {
        case 0:
            vert.position = float4(center.x - 20.0/wScale, center.y + 20.0/hScale, 0, 1);
            break;
        case 1:
            vert.position = float4(center.x - 20.0/wScale, center.y - 20.0/hScale, 0, 1);
            break;
        case 2:
            vert.position = float4(center.x + 20.0/wScale, center.y + 20.0/hScale, 0, 1);
            break;
        case 3:
            vert.position = float4(center.x + 20.0/wScale, center.y - 20.0/hScale, 0, 1);
            break;
    }
    vert.color = color_array[vid];
    return vert;
}

fragment float4 basic_fragment(ColoredVertex vert [[ stage_in ]]) {
    return vert.color;
}

//typedef struct {
//    vector_float2 position;
//    float textureIndex;
//    vector_float2 textureCoordinate;
//} TextureVertex;

struct RasterizerData {
    float4 position [[ position ]];
    //float2 textureCoordinate;
};

vertex RasterizerData textureVertexShader(unsigned int vid [[ vertex_id ]]) {
//    float2 pixelSpacePosition = vertexArray[vid].position;
//    float2 viewportSize = float2(*viewportSizePointer);
//
//    out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
//    out.position.xy = pixelSpacePosition.xy / viewportSize;
//
//    out.textureIndex = uint(vertexArray[vid].textureIndex);
//
    //    out.textureCoordinate = vertexArray[vid].textureCoordinate;
    RasterizerData out;
    switch (vid) {
        case 0:
            out.position = float4(-1.0, -1.0, 0.0, 1.0);
//            out.textureCoordinate = float2(0.0, 1.0);
            break;
        case 1:
            out.position = float4(-1.0, 1.0, 0.0, 1.0);
//            out.textureCoordinate = float2(0.0, 0.0);
            break;
        case 2:
            out.position = float4(1.0, -1.0, 0.0, 1.0);
//            out.textureCoordinate = float2(1.0, 1.0);
            break;
        case 3:
            out.position = float4(1.0, 1.0, 0.0, 1.0);
//            out.textureCoordinate = float2(1.0, 0.0);
            break;
    }
    return out;
}

fragment float4 textureFragmentShader(RasterizerData in [[ stage_in ]],
                                      const device packed_float2 *centers [[ buffer(0) ]],
                                      const device packed_float2 *distances [[ buffer(1) ]],
                                      const device float *rotations [[ buffer(2) ]],
                                      const device vector_uint2 *viewportSizePointer [[ buffer(3) ]],
                                      array<texture2d<half>, 2> textures [[ texture(0) ]]) {
    float2 viewportSize = float2(*viewportSizePointer);
    float2 center[2] = {centers[0] + (viewportSize / 2.0), centers[1] + (viewportSize / 2.0)}; // 0 ~ viewportSize
    float r[2] = {rotations[0], rotations[1]};
    float2 d[2] = {distances[0], distances[1]};
    
    float2 pixelPos = float2(in.position.xy);
    float2 samplingPos = float2(-1.0);
    
    int i = 0;
    for( ; i < 2; i++ ) {
        // limit drawing positions inside the viewportSize
        if(center[i].x < d[i].x) center[i].x = d[i].x;
        if(center[i].x > viewportSize.x - d[i].x) center[i].x = viewportSize.x - d[i].x;
        if(center[i].y < d[i].y) center[i].y = d[i].y;
        if(center[i].y > viewportSize.y - d[i].y) center[i].y = viewportSize.y - d[i].y;
        
        //float rad = 2.0 * M_PI_H * -r[i] / 360.0;
        float rad = -r[i];
        float2x2 reverseRotation = float2x2(cos(rad), sin(rad), -sin(rad), cos(rad));
        float2 rotatedPos;
        
        rotatedPos = reverseRotation * (pixelPos - center[i]);
        // define image the pixel belongs in or not
        if (rotatedPos.x >= 0.0 - d[i].x && rotatedPos.x <= d[i].x && rotatedPos.y >= 0.0 - d[i].y && rotatedPos.y <= d[i].y) {
            samplingPos = ( rotatedPos + d[i] ) / d[i] / 2.0;
            break;
        }
    }
    
    if (i >= 2) {
        return float4(1.0);
    }
    
    // sampling texture
    const sampler textureSampler (mag_filter::linear, min_filter::linear);
    const half4 colorSample = textures[i].sample(textureSampler, samplingPos);
    return float4(colorSample);
}
