package blocks

import mem "core:mem"

Atlas :: struct {
    tex_w, tex_h: f32, // 256,256
    tile_w, tile_h: f32, // 16,16
    cols, rows: int, // 16,16
    inset_px: f32, // 0.0 if using POINT filtering
}

atlas_make :: proc(inset_px: f32) -> Atlas {
    return Atlas{
        tex_w = 256,  tex_h = 256,
        tile_w = 16,  tile_h = 16,
        cols = 16,    rows = 16,
        inset_px = inset_px,
    }
}

atlas_uv_rect :: proc(a: ^Atlas, cell_index: int) -> UVRect {
    cx := cell_index % a.cols
    cy := cell_index / a.cols

    u0 := (cast(f32)cx * a.tile_w + a.inset_px) / a.tex_w
    v0 := (cast(f32)cy * a.tile_h + a.inset_px) / a.tex_h
    u1 := ((cast(f32)cx + 1) * a.tile_w - a.inset_px) / a.tex_w
    v1 := ((cast(f32)cy + 1) * a.tile_h - a.inset_px) / a.tex_h

    return UVRect{
        u0 = u0, v0 = v0, u1 = u1, v1 = v1,
        textureIndex = cell_index,
        frameCount = 1, frameDuration = 0,
    }
}

// --- Face mapping (override only when needed) ---

// If a block uses different tiles per face (e.g., Grass top/side/bottom),
// choose the appropriate cell; otherwise default to the enum's value.
tile_for_face :: proc(b: BlockType, f: Face) -> int {
    // Example override for Grass (fill these with the correct cells for your atlas)
    if b == .Grass {
        grass_top    := 0*16 + 0
        grass_bottom := 0*16 + 2 // dirt
        grass_side   := 1*16 + 0

        if f == .PY do return grass_top
        if f == .NY do return grass_bottom
        return grass_side // PX,NX,PZ,NZ
    }

    return cast(int)b
}

// Build the 6 (or 8) UVRects for a block from the atlas
gen_block_uvs :: proc(a: ^Atlas, b: BlockType) -> [8]UVRect {
    out: [8]UVRect // zero-initialized, mutable by default

    // Use half-open range 0..<6 for the 6 faces
    for face in 0..<6 {
        cell := tile_for_face(b, cast(Face)face)
        out[face] = atlas_uv_rect(a, cell)
    }

    return out
}



get_defaults :: proc(allocator: mem.Allocator) -> []Block {
    atlas := atlas_make(0.0)

    // Allocate the slice on the heap with the caller's allocator
    blocks := make([]Block, 2, allocator=allocator)

    blocks[0] = create_block(default_block_options("Stone", gen_block_uvs(&atlas, .Stone), .Stone, 1.5, 10.0, 1))
    blocks[1] = create_block(default_block_options("Dirt",  gen_block_uvs(&atlas, .Dirt),  .Dirt,  1.0,  2.0,  1))

    return blocks // safe: heap-backed
}
