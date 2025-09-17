#version 330 core

// Inputs from the vertex shader
in vec3 fragPosition_world;
in vec3 fragNormal_world;
in vec2 fragTexCoord;
in vec4 fragColor;

// Uniforms from our Odin code
uniform sampler2D texture0;
uniform sampler3D opacityData;
uniform vec3 sunDirection; // NEW: For dynamic lighting

out vec4 finalColor;

void main()
{
    // 1. Sample the block's texture and tint color
    vec4 atlasColor = texture(texture0, fragTexCoord);
    vec4 tintColor = fragColor / 255.0;

    // If the alpha is 0, discard the pixel (for leaves, etc.)
    if (atlasColor.a < 0.5) {
        discard;
    }

    // 2. Calculate Ambient Occlusion
    vec3 chunkOrigin = floor(fragPosition_world / vec3(32.0, 256.0, 32.0)) * vec3(32.0, 256.0, 32.0);
    vec3 localPos = fragPosition_world - chunkOrigin;
    float ao = 1.0 - texture(opacityData, localPos / vec3(32.0, 256.0, 32.0)).r;

    // 3. Calculate dynamic directional lighting
    float diffuse = max(dot(fragNormal_world, sunDirection), 0.0);
    float ambient = 0.4; // Constant ambient light to prevent pitch-black shadows
    float light = ambient + diffuse * (1.0 - ambient);

    // 4. Combine everything for the final color
    vec3 finalRGB = atlasColor.rgb * tintColor.rgb;
    finalRGB *= light * ao;

    finalColor = vec4(finalRGB, 1.0);
}