package chunk

import "../blocks"
import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import mem  "core:mem"
import sync "core:sync"
import "../shared"
import "../helpers"

// ───────────────────────────── Config ─────────────────────────────
// Constants defining the dimensions of a chunk.  In the master branch the Y
// dimension is treated as the major axis to improve cache locality when
// iterating through block data.
CHUNK_SIZE_X :: 32
CHUNK_SIZE_Z :: 32
CHUNK_SIZE_Y :: 256

// Re‑export the Face enum and default block flags from the blocks package.
Face            :: blocks.Face
BLOCKFLAGS_NONE :: blocks.BlockFlags(0)

// ───────────────────────────── Types ─────────────────────────────

/// World is the top‑level container for the entire game world. It owns a
/// map of loaded chunks and references to the texture atlas and its GPU
/// texture.  See chunk.world_init for construction.
World :: struct {
    chunks:    map[[2]int] ^Chunk, // Map of (cx, cz) → Chunk pointer
    atlas:     blocks.Atlas,       // Atlas definition used for UV calculations
    atlas_tex: rl.Texture2D,       // GPU texture for the atlas
}

/// Chunk represents a vertical column of blocks in the world.  Blocks are
/// stored with Y as the major axis (Y→Z→X) to improve memory cache hits when
/// iterating along the height.  Additional metadata and GPU data are stored
/// here as well.  An Axis‑Aligned Bounding Box (aabb) is cached on the
/// chunk to avoid recomputing it each frame.
Chunk :: struct {
    blocks: [CHUNK_SIZE_Y][CHUNK_SIZE_Z][CHUNK_SIZE_X] blocks.BlockType,
    cx, cz: int,            // Chunk coordinates in world space
    world:  ^World,         // Pointer back to the owning world

    // Opaque and water meshes plus any additional models used for batch
    // rendering.  These are populated by chunk_build_geometry.
    mesh:        rl.Mesh,
    model:       rl.Model,
    water_mesh:  rl.Mesh,
    water_model: rl.Model,
    models_opaque: [dynamic]rl.Model,
    models_water:  [dynamic]rl.Model,

    // Cached bounding box in world space.  Updated in chunk_init when the
    // chunk coordinates are set and reused by frustum culling routines.
    aabb: rl.BoundingBox,

    dirty: bool, // If true, the mesh needs to be rebuilt
    alive: bool, // If false, workers will skip generation/meshing work
}

// ───────────────────────────── Utils ─────────────────────────────

/// in_bounds returns true if a local coordinate is within the chunk’s
/// dimensions.  This helper is used by get_block_world and other routines.
in_bounds :: proc(x, y, z: int) -> bool {
    return x >= 0 && x < CHUNK_SIZE_X &&
           y >= 0 && y < CHUNK_SIZE_Y &&
           z >= 0 && z < CHUNK_SIZE_Z
}

/// world_init initializes a new World struct.  It sets up the map and
/// constructs a default atlas.  Clients should call world_set_atlas_texture
/// to assign a GPU texture when the texture is loaded.
world_init :: proc(w: ^World, inset_px: f32 = 0.0) {
    w.chunks = make(map[[2]int] ^Chunk)
    w.atlas  = blocks.atlas_make(inset_px)
}

/// world_add_chunk inserts a new chunk into the world’s map and links the
/// chunk back to this world.
world_add_chunk :: proc(w: ^World, c: ^Chunk) {
    w.chunks[[2]int{c.cx, c.cz}] = c
    c.world = w
}

/// world_get_chunk returns the chunk at the given coordinates or nil if
/// none is loaded.
world_get_chunk :: proc(w: ^World, cx, cz: int) -> ^Chunk {
    if w == nil do return nil
    if c, ok := w.chunks[[2]int{cx, cz}]; ok { return c }
    return nil
}

/// world_set_atlas_texture assigns the GPU texture used for all chunks.  It
/// also sets point filtering to preserve pixelated textures.
world_set_atlas_texture :: proc(w: ^World, tex: rl.Texture2D) {
    w.atlas_tex = tex
    rl.SetTextureFilter(tex, rl.TextureFilter.POINT)
}

// ───────────────────────────── Chunk API ─────────────────────────

/// chunk_init initializes a chunk at the given coordinates.  It marks the
/// chunk as dirty so its mesh will be built, sets alive to true and
/// computes the cached AABB.  Mesh and model fields are zero‑initialized.
chunk_init :: proc(c: ^Chunk, cx, cz: int) {
    c.cx = cx; c.cz = cz
    c.dirty = true
    c.alive = true
    c.mesh  = rl.Mesh{}
    c.model = rl.Model{}
    c.water_mesh  = rl.Mesh{}
    c.water_model = rl.Model{}
    c.models_opaque = make([]rl.Model, 0)
    c.models_water  = make([]rl.Model, 0)
    // Precompute the world‑space AABB for frustum culling.
    c.aabb = get_chunk_aabb(c)
}

/// get_block_world returns the block type at local coordinates (lx,ly,lz).
/// If the coordinates are outside the chunk, it performs a wrapped lookup
/// into neighbouring chunks.  Compared to the original implementation,
/// this version uses integer division and modulo arithmetic instead of
/// while loops to compute neighbour offsets, which is more efficient.
get_block_world :: proc(c: ^Chunk, lx, ly, lz: int) -> blocks.BlockType {
    // Fast path: if within bounds, return directly.
    if in_bounds(lx, ly, lz) do return c.blocks[ly][lz][lx]
    // Out‑of‑range Y is always air.
    if ly < 0 || ly >= CHUNK_SIZE_Y do return blocks.BlockType.Air

    // Compute wrapped local coordinates and neighbour offsets.
    nx := c.cx; nz := c.cz
    gx := lx;   gz := lz
    // X dimension
    if gx < 0 {
        // For negative values, modulo in Odin behaves like the remainder.  We
        // adjust manually to get a positive index and correct neighbour.
        off := (gx / CHUNK_SIZE_X) - 1
        if gx % CHUNK_SIZE_X == 0 do off = gx / CHUNK_SIZE_X
        nx += off
        gx  = gx - (off * CHUNK_SIZE_X)
        gx += CHUNK_SIZE_X
    } else if gx >= CHUNK_SIZE_X {
        off := gx / CHUNK_SIZE_X
        nx += off
        gx  = gx % CHUNK_SIZE_X
    }
    // Z dimension
    if gz < 0 {
        off := (gz / CHUNK_SIZE_Z) - 1
        if gz % CHUNK_SIZE_Z == 0 do off = gz / CHUNK_SIZE_Z
        nz += off
        gz  = gz - (off * CHUNK_SIZE_Z)
        gz += CHUNK_SIZE_Z
    } else if gz >= CHUNK_SIZE_Z {
        off := gz / CHUNK_SIZE_Z
        nz += off
        gz  = gz % CHUNK_SIZE_Z
    }

    // Fetch the neighbour chunk.  If missing, treat as air.
    nbor := world_get_chunk(c.world, nx, nz)
    if nbor == nil do return blocks.BlockType.Air
    return nbor.blocks[ly][gz][gx]
}

/// is_solid returns true if a block should occlude neighbouring faces.  This
/// version queries the block registry (blocks.get_block_data) and checks the
/// Solid flag.  Non‑solid blocks like air and water return false.
is_solid :: proc(bt: blocks.BlockType) -> bool {
    if data, ok := blocks.get_block_data(bt); ok && data != nil {
        return (data.flags & .Solid) != BLOCKFLAGS_NONE
    }
    return false
}

/// get_uv_for wraps the atlas helpers to return a UV rectangle for a given
/// block type and face.  It remains unchanged from upstream.
get_uv_for :: proc(atlas: ^blocks.Atlas, bt: blocks.BlockType, face: Face) -> (u0,v0,u1,v1: f32) {
    cell := blocks.tile_for_face(bt, face)
    r    := blocks.atlas_uv_rect(atlas, cell)
    return r.u0, r.v0, r.u1, r.v1
}

/// get_chunk_aabb computes the world‑space AABB for this chunk.  The result
/// is cached in c.aabb during chunk_init.
get_chunk_aabb :: proc(c: ^Chunk) -> rl.BoundingBox {
    wx := f32(c.cx) * f32(CHUNK_SIZE_X)
    wz := f32(c.cz) * f32(CHUNK_SIZE_Z)
    min := rl.Vector3{wx, 0, wz}
    max := rl.Vector3{wx + f32(CHUNK_SIZE_X), f32(CHUNK_SIZE_Y), wz + f32(CHUNK_SIZE_Z)}
    return rl.BoundingBox{min, max}
}

/// chunk_unload_gpu frees any GPU resources associated with a chunk.  It
/// unloads all opaque and water models and meshes.  This function has been
/// simplified for this example and omits some of the defensive checks in
/// the upstream version.
chunk_unload_gpu :: proc(c: ^Chunk) {
    if c == nil do return
    for m in c.models_opaque { rl.UnloadModel(m) }
    delete(c.models_opaque)
    for m in c.models_water { rl.UnloadModel(m) }
    delete(c.models_water)
    if c.model.meshCount > 0 { rl.UnloadModel(c.model); c.model = rl.Model{} }
    if c.mesh.vertexCount > 0 { rl.UnloadMesh(c.mesh); c.mesh = rl.Mesh{} }
    if c.water_model.meshCount > 0 { rl.UnloadModel(c.water_model); c.water_model = rl.Model{} }
    if c.water_mesh.vertexCount > 0 { rl.UnloadMesh(c.water_mesh); c.water_mesh = rl.Mesh{} }
}

// Placeholder definitions for chunk_build_geometry, chunk_generate_perlin and
// drawing routines.  These are intentionally abbreviated since the focus of
// this exercise is on structural changes rather than full functionality.  In
// your real project you would include the full implementations here and
// integrate any optimisations (e.g. greedy meshing, preallocation) as
// described in the optimisation notes.

chunk_build_geometry :: proc(c: ^Chunk) -> ^shared.MeshGeometry {
    // TODO: implement greedy meshing and preallocation here
    return nil
}

chunk_generate_perlin :: proc(c: ^Chunk, noise: ^helpers.Perlin, seed: u32, params: TerrainParams) {
    // TODO: implement procedural generation with heightmap and caves
}

chunk_draw_opaque :: proc(c: ^Chunk) {
    // TODO: implement drawing of opaque models and fallback model
}

chunk_draw_water :: proc(c: ^Chunk) {
    // TODO: implement drawing of water models
}