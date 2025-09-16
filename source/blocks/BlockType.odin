package blocks

// Mode B: give enum values the atlas cell index (row*16 + col).
// If you don't know exact cells yet, keep placeholders now, then adjust
// the integers later — all UV generation will pick it up automatically.
// Count (col,row) from top-left, 0-based; index = row*16 + col
BlockType :: enum u16 {
    // Core terrain
    Stone       = 0*16 + 1,      // (1,0)
    Dirt        = 0*16 + 2,      // (2,0)
    Grass       = 0*15 + 3,      // (3,0)  // ← default “side”; top/bottom are overridden in tile_for_face
    Grass_Top   = 0*16 + 0,
    
    // leave the rest as TODO until you confirm their cells with the overlay below
    Cobblestone      = 1*16 + 0,   // (1,1)  ← likely for this atlas; verify with overlay
    Bedrock          = 1*16 + 1,    // (6,0)  ← common location; verify
    Sand             = 1*16 + 2,    // (7,0)
    Gravel           = 1*16 + 3,    // (8,0)

    // placeholders (update these after checking with the overlay)
    OakLeaves        = 3*16 + 4,
    OakLog           = 1*16 + 5,
    Cactus           = 4*16 + 6,
    OakPlanks        = 1*16 + 4,
    Bricks           = 2*16 + 0,
    WoolRed          = 4*16 + 0,
    WoolGreen        = 4*16 + 5,
    WoolBlue         = 4*16 + 11,
    WoolYellow       = 4*16 + 4,
    Clay             = 2*16 + 2,
    Water            = 12*16 + 14,
    Lava             = 0*16 + 15,
    Snow             = 2*16 + 4,
    Slime            = 8*16 + 8,
    Model_Grass      = 9*16 + 0,
    Model_Deadbush   = 9*16 + 1,
    Model_Kelp       = 9*16 + 2,
    Flower_allium    = 12*16 + 0,
    Flower_orchid    = 12*16 + 1,
    Flower_tulip_red = 12*16 + 2,
    Flower_tulip_pink= 12*16 + 3,
    Flower_rose      = 12*16 + 4,
    Flower_dandelion = 12*16 + 5,

    UnknownBlockType = 15*16 + 15,
    Air              = 15*16 + 0,
}

