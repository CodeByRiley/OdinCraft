package blocks

Face :: enum u8 { PX, NX, PY, NY, PZ, NZ, Extra0, Extra1 }

UV2    :: struct { u, v: f32 }
UVRect :: struct {
    u0, v0, u1, v1: f32,
    textureIndex: int,
    frameCount: int,
    frameDuration: f32,
}

Block :: struct {
    name: cstring,
    solid: bool,
    gravity: bool,
    opaque: bool,
    produceLight: bool,
    uvs: [8]UVRect,   // one rect per face (0..5) + optional extras
    type: BlockType,
    hardness: f32,
    resistance: f32,
    harvestLevel: int,
}

BlockOptions :: struct {
    name: cstring,
    solid: bool,
    gravity: bool,
    opaque: bool,
    produceLight: bool,
    uvs: [8]UVRect,
    type: BlockType,
    hardness: f32,
    resistance: f32,
    harvestLevel: int,
}

default_block_options :: proc(name: cstring, uvs: [8]UVRect, block_type: BlockType, hardness: f32, resistance: f32, harvestLevel: int) -> BlockOptions {
    return BlockOptions{
        name = name,
        solid = true,
        gravity = false,
        opaque = true,
        produceLight = false,
        uvs = uvs,
        type = block_type,
        hardness = hardness,
        resistance = resistance,
        harvestLevel = harvestLevel,
    }
}

create_block :: proc(options: BlockOptions) -> Block {
    return Block{
        name = options.name,
        solid = options.solid,
        gravity = options.gravity,
        opaque = options.opaque,
        produceLight = options.produceLight,
        uvs = options.uvs,
        type = options.type,
        hardness = options.hardness,
        resistance = options.resistance,
        harvestLevel = options.harvestLevel,
    }
}