package blocks

// Mode B: give enum values the atlas cell index (row*16 + col).
// If you don't know exact cells yet, keep placeholders now, then adjust
// the integers later — all UV generation will pick it up automatically.
BlockType :: enum u16 {
    Grass            = 0*16 + 0,  // TODO: set to grass_side or logical default
    Dirt             = 0*16 + 2,  // (example) clay/dirt positions are placeholders
    Stone            = 0*16 + 1,
    Cobblestone      = 1*16 + 1,
    StoneBricks      = 6*16 + 0,
    CarvedStone      = 6*16 + 1,

    OakLeaves        = 3*16 + 4,
    SpruceLeaves     = 3*16 + 5,
    OakLog           = 1*16 + 5,

    Cactus           = 4*16 + 6,
    Sand             = 1*16 + 2,

    OakPlanks        = 1*16 + 4,
    AcaciaPlanks     = 5*16 + 4,
    DarkOakPlanks    = 5*16 + 5,

    Bricks           = 2*16 + 0,
    GlassWhite       = 1*16 + 3,

    Lamp_On          = 6*16 + 6,
    Lamp_Off         = 6*16 + 7,

    WoolRed          = 4*16 + 0,
    WoolGreen        = 4*16 + 5,
    WoolBlue         = 4*16 + 11,
    WoolYellow       = 4*16 + 4,

    Gravel           = 1*16 + 1,
    Clay             = 2*16 + 2,

    Water            = 0*16 + 13, // animated; still returns a cell index
    Lava             = 0*16 + 14, // animated
    Snow             = 2*16 + 4,
    Slime            = 8*16 + 8,  // placeholder

    // “Model_” entries are logical, not direct atlas cells (billboards, X-cross, etc.)
    Model_Grass      = 9*16 + 0,  // tall grass (cross model) placeholder
    Model_Deadbush   = 9*16 + 1,
    Model_Kelp       = 9*16 + 2,

    Flower_allium       = 12*16 + 0,
    Flower_orchid       = 12*16 + 1,
    Flower_tulip_red    = 12*16 + 2,
    Flower_tulip_pink   = 12*16 + 3,
    Flower_rose         = 12*16 + 4,
    Flower_dandelion    = 12*16 + 5,

    Bedrock          = 1*16 + 0,
    UnknownBlockType = 15*16 + 15,
    Air              = 15*16 + 0, // unused; just a sentinel
}
