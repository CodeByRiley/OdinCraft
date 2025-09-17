#version 450 core

// Input attributes with explicit locations matching Raylib's defaults
layout(location = 0) in vec3 vertexPosition;
layout(location = 1) in vec2 vertexTexCoord;
layout(location = 2) in vec3 vertexNormal;
layout(location = 3) in vec4 vertexColor;

// Uniforms provided by Raylib
uniform mat4 mvp;
uniform mat4 matModel;

// Outputs to the fragment shader with explicit locations
layout(location = 0) out vec3 fragPosition_world;
layout(location = 1) out vec3 fragNormal_world;
layout(location = 2) out vec2 fragTexCoord;
layout(location = 3) out vec4 fragColor;

void main()
{
    // Pass world-space position to the fragment shader
    fragPosition_world = vec3(matModel * vec4(vertexPosition, 1.0));

    // Pass other attributes straight through
    fragTexCoord = vertexTexCoord;
    fragColor = vertexColor;

    // Correctly transform the normal to world space and pass it
    fragNormal_world = normalize(mat3(transpose(inverse(matModel))) * vertexNormal);

    // Final vertex position for rendering
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}