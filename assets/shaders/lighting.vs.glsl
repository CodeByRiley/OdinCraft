#version 450 core

// Input attributes with Raylib's default names
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
in vec3 vertexNormal;

// Uniforms provided by Raylib
uniform mat4 mvp;
uniform mat4 matModel;

// Outputs to the fragment shader
out vec3 fragPosition_world; // Renamed to be clear
out vec3 fragNormal_world;
out vec2 fragTexCoord;
out vec4 fragColor;

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