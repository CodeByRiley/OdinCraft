package blocks

import mem "core:mem"

// The global block registry.
// We use a map because the BlockType enum values are sparse.
// The map stores pointers to heap-allocated BlockData to ensure stability.
REGISTRY: map[BlockType]^BlockData
BLOCKFLAGS_NONE :: BlockFlags(0)

// init_registry populates the REGISTRY with all block definitions.
// This MUST be called once at the start of your program.
init_registry :: proc(allocator := context.allocator) {
    // Ensure the map is initialized.
    REGISTRY = make(map[BlockType]^BlockData, allocator=allocator)
    
    atlas := atlas_make(0)

    // The nested procedure needs access to atlas and allocator.
    define_block :: proc(bt: BlockType, name: string, flags: BlockFlags, h, r, hl: u8, in_atlas: ^Atlas, in_allocator: mem.Allocator) {
        data := new(BlockData, in_allocator)
        data.name = name
        data.flags = flags
        data.uvs = gen_block_uvs(in_atlas, bt)
        data.hardness = h
        data.resistance = r
        data.harvestLevel = hl
        REGISTRY[bt] = data
    }
    // Define Air explicitly, though it has no properties.
    define_block(.Air, "Air", {}, 0, 0, 0, &atlas, allocator)
    
    // Terrain
    define_block(.Stone,       "Stone",       .Solid | .Opaque,                         15, 60, 1, &atlas, allocator)
    define_block(.Dirt,        "Dirt",        .Solid | .Opaque,                         5,  5,  0, &atlas, allocator)
    define_block(.Grass,       "Grass Block", .Solid | .Opaque,                         6,  5,  0, &atlas, allocator)
    define_block(.Cobblestone, "Cobblestone", .Solid | .Opaque,                         20, 60, 1, &atlas, allocator)
    define_block(.Bedrock,     "Bedrock",     .Solid | .Opaque,                         255, 255, 4, &atlas, allocator)
    define_block(.Sand,        "Sand",        .Solid | .Opaque | .Gravity,              5,  5,  0, &atlas, allocator)
    define_block(.Gravel,      "Gravel",      .Solid | .Opaque | .Gravity,              6,  5,  0, &atlas, allocator)

    // Plants
    define_block(.OakLog,      "Oak Log",     .Solid | .Opaque,                         20, 20, 0, &atlas, allocator)
    define_block(.OakLeaves,   "Oak Leaves",  .Solid,                                   2,  2,  0, &atlas, allocator)

    // Liquids
    define_block(.Water,       "Water",       .Is_Liquid,                               100, 100, 0, &atlas, allocator)
    define_block(.Lava,        "Lava",        .Is_Liquid | .Produce_Light,              100, 100, 0, &atlas, allocator)

    // Models (not solid, not opaque)
    define_block(.Model_Grass, "Grass",       .Is_Flora,                                0, 0, 0, &atlas, allocator)
}


// -------------------------- Accessors --------------------------

// get_block_data safely retrieves a pointer to a block's static data.
get_block_data :: proc(bt: BlockType) -> (data: ^BlockData, ok: bool) {
    data, ok = REGISTRY[bt]
    return
}

// is_solid checks a block's flag.
is_solid :: proc(bt: BlockType) -> bool {
    if data, ok := get_block_data(bt); ok {
        return (data.flags & .Solid) != BLOCKFLAGS_NONE
    }
    return false
}

// is_opaque checks a block's flag.
is_opaque :: proc(bt: BlockType) -> bool {
    if data, ok := get_block_data(bt); ok {
        return (data.flags & .Opaque) != BLOCKFLAGS_NONE
    }
    return false
}

Atlas :: struct {
    tex_w, tex_h, tile_w, tile_h, cols, rows, inset_px: u16,
}

atlas_make :: proc(inset_px: u16) -> Atlas {
    return {tex_w=256, tex_h=256, tile_w=16, tile_h=16, cols=16, rows=16, inset_px=inset_px}
}

atlas_uv_rect :: proc(a: ^Atlas, cell_index: u16) -> UVRect {
    // clamp cell to atlas bounds (prevents out-of-range)
    max_cell := a.cols*a.rows - 1
    ci := cell_index
    if ci > max_cell do ci = max_cell

    cx := ci % a.cols
    cy := ci / a.cols

    tw := f32(a.tile_w)
    th := f32(a.tile_h)
    iw := f32(a.inset_px)
    W  := f32(a.tex_w)
    H  := f32(a.tex_h)

    u0 := (f32(cx)*tw + iw) / W
    v0 := (f32(cy)*th + iw) / H
    u1 := ((f32(cx)+1)*tw - iw) / W
    v1 := ((f32(cy)+1)*th - iw) / H

    return UVRect{u0, v0, u1, v1, ci, 1, 0}
}

tile_for_face :: proc(b: BlockType, f: Face) -> u16 {
    if b == .Grass {
        if f == .PY do return 0*16 + 0 // Grass Top texture
        if f == .NY do return 1*16 + 0 // Dirt texture
        return 0*16 + 3               // Grass Side texture
    }
    return cast(u16)b
}

gen_block_uvs :: proc(a: ^Atlas, b: BlockType) -> [8]UVRect {
    out: [8]UVRect
    for face in 0..<6 {
        cell := tile_for_face(b, cast(Face)face)
        out[face] = atlas_uv_rect(a, cell)
    }
    return out
}