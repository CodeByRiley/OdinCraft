package chunk

import "../blocks"
import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import mem "core:mem"
import sync "core:sync"
import "../shared"
import "../helpers"

// ───────────────────────────── Config ─────────────────────────────
CHUNK_SIZE_X :: 32
CHUNK_SIZE_Z :: 32
CHUNK_SIZE_Y :: 256
Face :: blocks.Face
BLOCKFLAGS_NONE :: blocks.BlockFlags(0)

// ───────────────────────────── Types ─────────────────────────────

World :: struct {
    chunks:    map[[2]int] ^Chunk,
    atlas:     blocks.Atlas,
    atlas_tex: rl.Texture2D,
}

Chunk :: struct {
    // CORRECTED LAYOUT: Y is the major axis for cache efficiency.
    blocks: [CHUNK_SIZE_Y][CHUNK_SIZE_Z][CHUNK_SIZE_X] blocks.BlockType,
    cx, cz: int,
    world:  ^World,
    mesh:  rl.Mesh,
    model: rl.Model,
    water_mesh:  rl.Mesh,
    water_model: rl.Model,
    models_opaque: [dynamic]rl.Model,
    models_water:  [dynamic]rl.Model,
    dirty: bool,
    alive: bool,
}

// ───────────────────────────── Utils ─────────────────────────────
// (in_bounds, make_rl_copy, FaceInfo, FACE_DATA, NEI, face_tint are all correct and unchanged)
in_bounds :: proc(x, y, z: int) -> bool {
    return x >= 0 && x < CHUNK_SIZE_X &&
           y >= 0 && y < CHUNK_SIZE_Y &&
           z >= 0 && z < CHUNK_SIZE_Z
}
make_rl_copy :: proc($T: typeid, src: []T) -> ^T {
    n := len(src)
    if n == 0 do return nil
    total := cast(u32)(n * size_of(T))
    p := cast(^T) rl.MemAlloc(total)
    dst := mem.slice_ptr(p, n)
    for i in 0..<n do dst[i] = src[i]
    return p
}
FaceInfo :: struct { nrm: rl.Vector3, corners: [4]rl.Vector3 }
FACE_DATA := [6]FaceInfo{
	{ nrm = {+1,0,0}, corners = [4]rl.Vector3{{1,0,0},{1,1,0},{1,1,1},{1,0,1}} }, // Positive X
	{ nrm = {-1,0,0}, corners = [4]rl.Vector3{{0,0,1},{0,1,1},{0,1,0},{0,0,0}} }, // Negative X
	{ nrm = {0,+1,0}, corners = [4]rl.Vector3{{0,1,1},{1,1,1},{1,1,0},{0,1,0}} }, // Positive Y (Top)
	{ nrm = {0,-1,0}, corners = [4]rl.Vector3{{0,0,0},{1,0,0},{1,0,1},{0,0,1}} }, // Negative Y (Bottom)
	{ nrm = {0,0,+1}, corners = [4]rl.Vector3{{0,0,1},{1,0,1},{1,1,1},{0,1,1}} }, // Positive Z
	{ nrm = {0,0,-1}, corners = [4]rl.Vector3{{1,0,0},{0,0,0},{0,1,0},{1,1,0}} }, // Negative Z
}
NEI := [6][3]int{ {+1,0,0},{-1,0,0}, {0,+1,0},{0,-1,0}, {0,0,+1},{0,0,-1} }
GRASS_TINT  := rl.Color{118,182,76,255}
LEAVES_TINT := rl.Color{127,178,56,255}
WATER_TINT  := rl.Color{63,118,228,180}
face_tint :: proc(bt: blocks.BlockType, face: Face) -> rl.Color {
	if bt == blocks.BlockType.Grass && face == Face.PY { return GRASS_TINT }
	if bt == blocks.BlockType.OakLeaves do return LEAVES_TINT
	if bt == blocks.BlockType.Water     do return WATER_TINT
	return rl.WHITE
}

// ───────────────────────────── World API ─────────────────────────
// (world_* functions are all correct and unchanged)
world_init :: proc(w: ^World, inset_px: u16 = 0.0) {
	w.chunks = make(map[[2]int] ^Chunk)
	w.atlas  = blocks.atlas_make(inset_px)
}
world_add_chunk :: proc(w: ^World, c: ^Chunk) {
	w.chunks[[2]int{c.cx, c.cz}] = c
	c.world = w
}
world_get_chunk :: proc(w: ^World, cx, cz: int) -> ^Chunk {
	if w == nil do return nil
	if c, ok := w.chunks[[2]int{cx, cz}]; ok { return c }
	return nil
}
world_set_atlas_texture :: proc(w: ^World, tex: rl.Texture2D) {
	w.atlas_tex = tex
	rl.SetTextureFilter(tex, rl.TextureFilter.POINT)
}

// ───────────────────────────── Chunk API ─────────────────────────

chunk_init :: proc(c: ^Chunk, cx, cz: int) {
    c.cx = cx; c.cz = cz
    c.dirty = true
    c.alive = true // Set the chunk as alive upon creation.
    c.mesh  = rl.Mesh{}
    c.model = rl.Model{}

    for y in 0..<CHUNK_SIZE_Y {
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
                c.blocks[y][z][x] = blocks.BlockType.Air
            }
        }
    }
}

chunk_set :: proc(c: ^Chunk, x, y, z: int, bt: blocks.BlockType) {
    if !in_bounds(x,y,z) do return

    c.blocks[y][z][x] = bt
    c.dirty = true
}

chunk_get :: proc(c: ^Chunk, x, y, z: int) -> blocks.BlockType {
    if !in_bounds(x,y,z) do return blocks.BlockType.Air

    return c.blocks[y][z][x]
}

get_block_world :: proc(c: ^Chunk, lx, ly, lz: int) -> blocks.BlockType {
    if in_bounds(lx,ly,lz) do return c.blocks[ly][lz][lx]
    if ly < 0 || ly >= CHUNK_SIZE_Y do return blocks.BlockType.Air

    nx, nz := c.cx, c.cz
    gx, gz := lx, lz
    for gx < 0             { gx += CHUNK_SIZE_X; nx -= 1 }
    for gx >= CHUNK_SIZE_X { gx -= CHUNK_SIZE_X; nx += 1 }
    for gz < 0             { gz += CHUNK_SIZE_Z; nz -= 1 }
    for gz >= CHUNK_SIZE_Z { gz -= CHUNK_SIZE_Z; nz += 1 }

    nbor := world_get_chunk(c.world, nx, nz)
    if nbor == nil do return blocks.BlockType.Air

    return nbor.blocks[ly][gz][gx]
}

// ... (Other helpers like is_solid, get_uv_for, unload_gpu, aabb are correct) ...
is_solid :: proc(bt: blocks.BlockType) -> bool {
    // This should use your registry's is_solid now
    if data, ok := blocks.get_block_data(bt); ok && data != nil {
        return (data.flags & .Solid) != BLOCKFLAGS_NONE
    }
    return false
}

get_uv_for :: proc(atlas: ^blocks.Atlas, bt: blocks.BlockType, face: Face) -> (u0,v0,u1,v1: f32) {
	cell := blocks.tile_for_face(bt, face)
	r    := blocks.atlas_uv_rect(atlas, cell)
	return r.u0, r.v0, r.u1, r.v1
}

chunk_unload_gpu :: proc(c: ^Chunk) {
    if c == nil do return
    for i in 0..<len(c.models_opaque) { if c.models_opaque[i].meshCount > 0 { rl.UnloadModel(c.models_opaque[i]) } }
    delete(c.models_opaque)
    for i in 0..<len(c.models_water) { if c.models_water[i].meshCount > 0 { rl.UnloadModel(c.models_water[i]) } }
    delete(c.models_water)
    if c.model.meshCount > 0 { rl.UnloadModel(c.model); c.model = rl.Model{}; c.mesh = rl.Mesh{}
    } else if c.mesh.vertexCount > 0 { rl.UnloadMesh(c.mesh); c.mesh = rl.Mesh{} }
    if c.water_model.meshCount > 0 { rl.UnloadModel(c.water_model); c.water_model = rl.Model{}; c.water_mesh  = rl.Mesh{}
    } else if c.water_mesh.vertexCount > 0 { rl.UnloadMesh(c.water_mesh); c.water_mesh = rl.Mesh{} }
}

get_chunk_aabb :: proc(c: ^Chunk) -> rl.BoundingBox {
	wx := f32(c.cx) * f32(CHUNK_SIZE_X)
	wz := f32(c.cz) * f32(CHUNK_SIZE_Z)
	min := rl.Vector3{wx, 0, wz}
	max := rl.Vector3{wx + f32(CHUNK_SIZE_X), f32(CHUNK_SIZE_Y), wz + f32(CHUNK_SIZE_Z)}
	return rl.BoundingBox{min, max}
}

// ───────────────── Meshing (Worker Thread) ─────────────────

chunk_build_geometry :: proc(c: ^Chunk) -> ^shared.MeshGeometry {
    geo := new(shared.MeshGeometry)
    
    // CORRECTED: Loop order is Y -> Z -> X to match memory layout for max speed.
    for y in 0..<CHUNK_SIZE_Y {
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
            
                bt := c.blocks[y][z][x]
                if bt == blocks.BlockType.Air do continue
                is_water := bt == blocks.BlockType.Water

                for f in 0..<6 {
                    nx := x + NEI[f][0]; ny := y + NEI[f][1]; nz := z + NEI[f][2]
                    nb := get_block_world(c, nx, ny, nz)

                    if !is_water {
                        if is_solid(nb) do continue
                    } else {
                        if nb == blocks.BlockType.Water do continue
                    }

                    vertsP := &geo.vertsO; normsP := &geo.normsO; uvsP := &geo.uvsO; colorsP := &geo.colorsO; idxP := &geo.idxO
                    if is_water {
                        vertsP = &geo.vertsW; normsP = &geo.normsW; uvsP = &geo.uvsW; colorsP = &geo.colorsW; idxP = &geo.idxW
                    }
                    
                    face := FACE_DATA[f]
                    base := cast(u16)(len(vertsP^) / 3)
                    u0, v0, u1, v1 := get_uv_for(&c.world.atlas, bt, cast(Face)f)
                    
                    for k in 0..<4 {
                        co := face.corners[k]
                        px := cast(f32)(c.cx*CHUNK_SIZE_X + x) + co.x
                        py := cast(f32)(y)                         + co.y
                        pz := cast(f32)(c.cz*CHUNK_SIZE_Z + z) + co.z
                        append(vertsP, px, py, pz)
                        append(normsP, face.nrm.x, face.nrm.y, face.nrm.z)

                        s, t: f32
                        switch f {
                        case 0: s = co.z; t = 1.0 - co.y; case 1: s = 1.0 - co.z; t = 1.0 - co.y
                        case 2: s = co.x; t = co.z;       case 3: s = co.x; t = 1.0 - co.z
                        case 4: s = 1.0 - co.x; t = 1.0 - co.y; case 5: s = co.x; t = 1.0 - co.y
                        }
                        u := u0 + (u1 - u0)*s; v := v0 + (v1 - v0)*t
                        append(uvsP, u, v)

                        col := face_tint(bt, cast(Face)f)
                        append(colorsP, col.r, col.g, col.b, col.a)
                    }
                    append(idxP, base+0, base+1, base+2)
                    append(idxP, base+0, base+2, base+3)
                }
            }
        }
    }
    return geo
}

// ───────────────── GPU Upload (Main Thread) ─────────────────

chunk_upload_geometry :: proc(c: ^Chunk, geo: ^shared.MeshGeometry) {
    chunk_unload_gpu(c)

    // Opaque
    if len(geo.idxO) > 0 {
        c.mesh.vertexCount   = cast(i32)(len(geo.vertsO)/3)
        c.mesh.triangleCount = cast(i32)(len(geo.idxO)/3)
        c.mesh.vertices      = make_rl_copy(f32, geo.vertsO[:])
        c.mesh.normals       = make_rl_copy(f32, geo.normsO[:])
        c.mesh.texcoords     = make_rl_copy(f32, geo.uvsO[:])
        c.mesh.colors        = make_rl_copy(u8,  geo.colorsO[:])
        c.mesh.indices       = make_rl_copy(u16, geo.idxO[:])
        rl.UploadMesh(&c.mesh, false)
        c.model = rl.LoadModelFromMesh(c.mesh)
        rl.SetMaterialTexture(&c.model.materials[0], rl.MaterialMapIndex.ALBEDO, c.world.atlas_tex)
    }

    // Water
    if len(geo.idxW) > 0 {
        c.water_mesh.vertexCount   = cast(i32)(len(geo.vertsW)/3)
        c.water_mesh.triangleCount = cast(i32)(len(geo.idxW)/3)
        c.water_mesh.vertices      = make_rl_copy(f32, geo.vertsW[:])
        c.water_mesh.normals       = make_rl_copy(f32, geo.normsW[:])
        c.water_mesh.texcoords     = make_rl_copy(f32, geo.uvsW[:])
        c.water_mesh.colors        = make_rl_copy(u8,  geo.colorsW[:])
        c.water_mesh.indices       = make_rl_copy(u16, geo.idxW[:])
        rl.UploadMesh(&c.water_mesh, false)
        c.water_model = rl.LoadModelFromMesh(c.water_mesh)
        rl.SetMaterialTexture(&c.water_model.materials[0], rl.MaterialMapIndex.ALBEDO, c.world.atlas_tex)
    }

    delete(geo.vertsO); delete(geo.normsO); delete(geo.uvsO); delete(geo.colorsO); delete(geo.idxO)
    delete(geo.vertsW); delete(geo.normsW); delete(geo.uvsW); delete(geo.colorsW); delete(geo.idxW)
    free(geo)
    c.dirty = false
}

// ───────────────── World Generation ─────────────────
// (TerrainParams struct and default_terrain_params are correct and unchanged)
TerrainParams :: struct {
	scale: f32, octaves: int, lacunarity: f32, gain: f32, amplitude: f32,
	sea_level: int, top_soil: int, caves: bool, cave_scale: f32, cave_octaves: int,
	cave_lacunarity: f32, cave_gain: f32, cave_threshold: f32, block_stone: blocks.BlockType,
	block_dirt: blocks.BlockType, block_grass: blocks.BlockType, use_water: bool, block_water: blocks.BlockType,
}
default_terrain_params :: proc() -> TerrainParams {
	return {
		scale = 128.0, octaves = 5, lacunarity = 2.0, gain = 0.5, amplitude = 40.0,
		sea_level = 62, top_soil = 3, caves = true, cave_scale = 96.0, cave_octaves = 3,
		cave_lacunarity = 2.0, cave_gain = 0.5, cave_threshold = 0.55,
		block_stone = .Stone, block_dirt = .Dirt, block_grass = .Grass,
		block_water = .Water, use_water = true,
	}
}

chunk_generate_perlin :: proc(c: ^Chunk, noise: ^helpers.Perlin, seed: u32, params: TerrainParams) {
    // FINAL SAFEGUARD: Initial check before any work is done.
    if !sync.atomic_load(&c.alive) {
        return
    }

    heights: [CHUNK_SIZE_X][CHUNK_SIZE_Z]int

    // --- Pass 1: Stone and Water ---
    for z in 0..<CHUNK_SIZE_Z {
        for x in 0..<CHUNK_SIZE_X {
            // SAFE POINT 1: Check periodically during the most expensive part of Pass 1.
            // We check once per column.
            if !sync.atomic_load(&c.alive) {
                return // Abort generation
            }

            gx := c.cx*CHUNK_SIZE_X + x; gz := c.cz*CHUNK_SIZE_Z + z
            nx := cast(f32)(gx) / params.scale; nz := cast(f32)(gz) / params.scale
            hnoise := helpers.fbm2(noise, nx, nz, params.octaves, params.lacunarity, params.gain)
            height := params.sea_level + cast(int)(params.amplitude * hnoise)
            if height < 1 { height = 1 }
            if height > CHUNK_SIZE_Y-2 { height = CHUNK_SIZE_Y-2 }
            heights[x][z] = height

            for y in 0..=height {
                c.blocks[y][z][x] = params.block_stone
            }
            if params.use_water && params.sea_level > height {
                for y in height+1..=params.sea_level {
                    if y >= 0 && y < CHUNK_SIZE_Y {
                        c.blocks[y][z][x] = params.block_water
                    }
                }
            }
        }
    }

    // --- Pass 2: Caves ---
    if params.caves {
        inv := 1.0 / params.cave_scale
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
                top := heights[x][z]
                for y in 1..=top {
                    // SAFE POINT 2: Check every 16 blocks down during cave carving.
                    if (y & 15) == 0 && !sync.atomic_load(&c.alive) {
                        return // Abort generation
                    }

                    nx := cast(f32)(c.cx*CHUNK_SIZE_X + x) * inv
                    ny := cast(f32)(y) * inv
                    nz := cast(f32)(c.cz*CHUNK_SIZE_Z + z) * inv
                    n3 := helpers.fbm3(noise, nx, ny, nz, params.cave_octaves, params.cave_lacunarity, params.cave_gain)
                    if n3 > params.cave_threshold {
                        c.blocks[y][z][x] = blocks.BlockType.Air
                    }
                }
            }
        }
    }

    // --- Pass 3: Topsoil ---
    for z in 0..<CHUNK_SIZE_Z {
        for x in 0..<CHUNK_SIZE_X {
            // SAFE POINT 3: Check once per column before the final pass.
            if !sync.atomic_load(&c.alive) {
                return // Abort generation
            }
            
            y := CHUNK_SIZE_Y - 1
            for y >= 1 {
                if c.blocks[y][z][x] != blocks.BlockType.Air do break
                y -= 1
            }
            if y < 1 do continue

            if c.blocks[y][z][x] == params.block_stone {
                c.blocks[y][z][x] = params.block_grass
                for d in 1..=params.top_soil {
                    yy := y - d
                    if yy <= 0 do break
                    if c.blocks[yy][z][x] == params.block_stone {
                        c.blocks[yy][z][x] = params.block_dirt
                    }
                }
            }
        }
    }
    
    c.dirty = true
}

// ───────────────── Drawing ─────────────────
// (chunk_draw_opaque and chunk_draw_water are correct and unchanged)
chunk_draw_opaque :: proc(c: ^Chunk) {
    for m in c.models_opaque { rl.DrawModel(m, {0,0,0}, 1.0, rl.WHITE) }
    if c.model.meshCount > 0 { rl.DrawModel(c.model, {0,0,0}, 1.0, rl.WHITE) }
}
chunk_draw_water :: proc(c: ^Chunk) {
    rl.BeginBlendMode(rl.BlendMode.ALPHA)
    rlgl.DisableDepthMask()
    for m in c.models_water { rl.DrawModel(m, {0,0,0}, 1.0, rl.WHITE) }
    if c.water_model.meshCount > 0 { rl.DrawModel(c.water_model, {0,0,0}, 1.0, rl.WHITE) }
    rlgl.EnableDepthMask()
    rl.EndBlendMode()
}