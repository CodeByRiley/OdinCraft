package blocks

// BlockType uses the block's default atlas cell index as its value.
// This is an efficient way to link a block ID directly to its primary texture.
BlockType :: enum u16 {
    // Core terrain
    Stone           = 0*16 + 1,  // (1,1) in new standard atlas
    Dirt            = 0*16 + 2,  // (0,1)
    Grass           = 0*16 + 3,
    
    // Ores & Minerals
    Cobblestone     = 1*16 + 0,
    Bedrock         = 1*16 + 1,
    Sand            = 2*16 + 2,
    Gravel          = 2*16 + 3,
    
    // Wood & Plants
    OakLog          = 1*16 + 4,
    OakLeaves       = 2*16 + 4,
    OakPlanks       = 0*16 + 4,
    Cactus          = 3*16 + 5,

    // Man-made
    Bricks          = 0*16 + 7,
    WoolRed         = 8*16 + 1,
    WoolGreen       = 8*16 + 2,
    WoolBlue        = 8*16 + 3,
    WoolYellow      = 8*16 + 4,
    
    // Liquids & Specials
    Water           = 13*16 + 14,
    Lava            = 14*16 + 14,
    
    // Models & Flora
    Model_Grass     = 0*16 + 8,
    Model_Deadbush  = 3*16 + 8,

    // Special Values
    Unknown         = 15*16 + 15,
    Air             = 0,          
}

// Face represents the six cardinal directions of a cube's face.
Face :: enum u8 { PX, NX, PY, NY, PZ, NZ, Extra0, Extra1 }

// BlockFlags uses a bitfield to pack 8 boolean properties into a single byte.
BlockFlags :: enum u8 {
    Solid         = 1 << 0, // Has collision and occludes neighbors.
    Opaque        = 1 << 1, // Rendered in the opaque pass.
    Gravity       = 1 << 2, // Affected by gravity.
    Produce_Light = 1 << 3, // Emits light.
    Is_Liquid     = 1 << 4, // Behaves like water or lava.
    Is_Flora      = 1 << 5, // Is a non-solid plant model (like grass, flowers).
}

// UVRect defines the bounding box of a texture within a larger atlas.
UVRect :: struct {
    u0, v0, u1, v1: f32,
    textureIndex:   u16,
    frameCount:     u8,
    frameDuration:  u8,
}

// BlockData holds the STATIC properties for a type of block.
// This data is stored once per block type in the registry.
BlockData :: struct {
    name:         string,
    flags:        BlockFlags,
    uvs:          [8]UVRect,
    hardness:     u8,
    resistance:   u8,
    harvestLevel: u8,
}