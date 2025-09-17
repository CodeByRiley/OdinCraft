#version 460 core

in vec3 fragPosition;
in vec2 fragTexCoord;
in vec4 fragColor;
in vec3 fragNormal;

uniform sampler2D texture0;
uniform sampler3D opacityData;
uniform sampler3D lightData;

uniform int debugMode;

out vec4 finalColor;

// (The AO kernel is unchanged)
const int KERNEL_SIZE = 8;
const vec3 kernel[KERNEL_SIZE] = vec3[](
    vec3( 0.5,  0.5,  0.5), vec3( 0.5,  0.5, -0.5),
    vec3( 0.5, -0.5,  0.5), vec3( 0.5, -0.5, -0.5),
    vec3(-0.5,  0.5,  0.5), vec3(-0.5,  0.5, -0.5),
    vec3(-0.5, -0.5,  0.5), vec3(-0.5, -0.5, -0.5)
);

void main()
{
    vec3 chunkOrigin = floor(fragPosition / vec3(32.0, 256.0, 32.0)) * vec3(32.0, 256.0, 32.0);
    vec4 atlasColor = texture(texture0, fragTexCoord);
    vec4 tintColor  = fragColor / 255.0;

    float occlusion = 0.0;
    float sampleRadius = 0.8;
    for(int i = 0; i < KERNEL_SIZE; i++)
    {
        vec3 samplePos = fragPosition + kernel[i] * sampleRadius;
        vec3 texCoord3D = (samplePos - chunkOrigin) / vec3(32.0, 256.0, 32.0);
        occlusion += texture(opacityData, texCoord3D).r;
    }
    float aoFactor = 1.0 - (occlusion / float(KERNEL_SIZE));

    vec3 lightTexCoord = (fragPosition - chunkOrigin) / vec3(32.0, 256.0, 32.0);
    float lightFactor = texture(lightData, lightTexCoord).r;

    vec3 finalRGB = atlasColor.rgb * tintColor.rgb;
    finalRGB *= (aoFactor * 0.7 + 0.3);
    finalRGB *= (lightFactor * 0.9 + 0.1);

    // --- NEW: Debug Visualization Logic ---
    if (debugMode == 0) {
        // Mode 0: Normal rendering
        finalColor = vec4(finalRGB, atlasColor.a);
    } else if (debugMode == 1) {
        // Mode 1: Visualize Atlas Texture
        finalColor = atlasColor;
    } else if (debugMode == 2) {
        // Mode 2: Visualize Tint Color
        finalColor = tintColor;
    } else if (debugMode == 3) {
        // Mode 3: Visualize Light Map
        finalColor = vec4(vec3(lightFactor), 1.0);
    } else if (debugMode == 4) {
        // Mode 4: Visualize Ambient Occlusion
        finalColor = vec4(vec3(aoFactor), 1.0);
    } else {
        // Error color if mode is invalid
        finalColor = vec4(1.0, 0.0, 1.0, 1.0); // Magenta
    }
}