#version 330 core

// Input vertex attributes from your mesh data
in vec3 vertexPosition;
in vec2 vertexTexCoord;
in vec4 vertexColor;
in vec3 vertexNormal;

// Input uniform values provided by Raylib automatically
uniform mat4 mvp;        // Model-View-Projection matrix
uniform mat4 matModel;   // Model-to-World matrix

// Output attributes (varyings) to be sent to the fragment shader
out vec3 fragPosition;   // The world-space position of the fragment
out vec2 fragTexCoord;   // The UV coordinate for the texture atlas
out vec4 fragColor;      // The vertex color (used for tinting)
out vec3 fragNormal;     // The world-space normal of the fragment

void main()
{
    // --- Pass data to the Fragment Shader ---

    // Calculate the world-space position of the vertex and pass it on.
    // The fragment shader needs this to sample the 3D textures correctly.
    fragPosition = vec3(matModel * vec4(vertexPosition, 1.0));

    // Pass the texture coordinate and color straight through.
    fragTexCoord = vertexTexCoord;
    fragColor    = vertexColor;

    // Calculate the world-space normal, normalize it, and pass it on.
    // This is important for lighting and orienting the AO kernel.
    // (w = 0.0 for normals so they are not affected by translation)
    fragNormal   = normalize(vec3(matModel * vec4(vertexNormal, 0.0)));


    // --- Final Vertex Position ---

    // Calculate the final clip-space position of the vertex.
    // This is the mandatory output that tells OpenGL where to draw the vertex.
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}