package chunk

import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import gl "vendor:OpenGL"
import mem "core:mem"
import sync "core:sync"
import fmt "core:fmt"
import "../helpers"
import "../blocks"
import "../shared"

// ───────────────────────────── Config ─────────────────────────────
CHUNK_SIZE_X :: 32
CHUNK_SIZE_Z :: 32
CHUNK_SIZE_Y :: 256
MAX_LIGHT      :: u8(15)
AO_TABLE := [4]f32{ 0.125, 0.20, 0.40, 0.60 }
TOP_FACE_AO_BIAS :: f32(0.25) // blend 25% toward 1.0 on +Y faces
MIN_LIGHT_BIAS :: f32(0.08)   // tiny ambient floor so nothing is pitch-black
BLOCKFLAGS_NONE :: blocks.BlockFlags(0)

// ───────────────────────────── Types ─────────────────────────────
Face :: blocks.Face

World :: struct {
    chunks:    map[[2]int] ^Chunk,
    atlas:     blocks.Atlas,
    atlas_tex: rl.Texture2D,
}

Chunk :: struct {
    blocks: [CHUNK_SIZE_Y][CHUNK_SIZE_Z][CHUNK_SIZE_X] blocks.BlockType,

    // light volumes (per-voxel)
    sky_light:   [CHUNK_SIZE_Y][CHUNK_SIZE_Z][CHUNK_SIZE_X] u8,
    block_light: [CHUNK_SIZE_Y][CHUNK_SIZE_Z][CHUNK_SIZE_X] u8,
    lights_ready: bool,

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

    opacity_tex_id: u32,
    light_tex_id:   u32,
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
	c.lights_ready = false
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
    c.lights_ready = false
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

get_chunk_and_local :: proc(
    c: ^Chunk, lx, ly, lz: int
) -> (cc: ^Chunk, x: int, y: int, z: int) {
    if ly < 0 || ly >= CHUNK_SIZE_Y {
        return nil, 0, 0, 0
    }

    nx := c.cx
    nz := c.cz
    gx := lx
    gz := lz

    for gx < 0             { gx += CHUNK_SIZE_X; nx -= 1 }
    for gx >= CHUNK_SIZE_X { gx -= CHUNK_SIZE_X; nx += 1 }
    for gz < 0             { gz += CHUNK_SIZE_Z; nz -= 1 }
    for gz >= CHUNK_SIZE_Z { gz -= CHUNK_SIZE_Z; nz += 1 }

    nbor := world_get_chunk(c.world, nx, nz)
    if nbor == nil {
        return nil, 0, 0, 0
    }

    return nbor, gx, ly, gz
}

get_sky_light_world :: proc(c: ^Chunk, lx, ly, lz: int) -> u8 {
    cc, x, y, z := get_chunk_and_local(c, lx, ly, lz)
    if cc == nil || !cc.lights_ready { // neighbor missing OR not lit yet
        return MAX_LIGHT              // treat as open sky
    }
    return cc.sky_light[y][z][x]
}

get_block_light_world :: proc(c: ^Chunk, lx, ly, lz: int) -> u8 {
    cc, x, y, z := get_chunk_and_local(c, lx, ly, lz)
    if cc == nil || !cc.lights_ready {
        return 0
    }
    return cc.block_light[y][z][x]
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

_create_voxel_texture_3d :: proc(width, height, depth: int, data: rawptr) -> u32 {
    tex_id: u32 = 0;
    helpers.GL_GenTextures(1, &tex_id);
    helpers.GL_BindTexture(gl.TEXTURE_3D, tex_id);

    helpers.GL_TexImage3D(
        gl.TEXTURE_3D,       // target
        0,                   // level
        gl.R8,               // internalformat
        i32(width),          // width
        i32(height),         // height
        i32(depth),          // depth
        0,                   // border
        gl.RED,              // format
        gl.UNSIGNED_BYTE,    // type
        data,                // pixels
    );

    // COMPLETE PARAMETERS: You must set min/mag filter and S/T/R wrap modes.
    helpers.GL_TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    helpers.GL_TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    helpers.GL_TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    helpers.GL_TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    helpers.GL_TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);

    helpers.GL_BindTexture(gl.TEXTURE_3D, 0);
    return tex_id;
}

// _create_voxel_texture_3d :: proc(width, height, depth: int, data: rawptr) -> u32 {
//     tex_id: u32 = 0;

//     // 1. Generate a texture name (ID) from OpenGL
//     gl.GenTextures(1, &tex_id);

//     // 2. Bind the texture to the GL_TEXTURE_3D target
//     gl.BindTexture(gl.TEXTURE_3D, tex_id);

//     // 3. Upload the texture data
//     // This is the core function that allocates GPU memory and copies your data.
//     gl.TexImage3D(
//         gl.TEXTURE_3D,       // target
//         0,                   // level of detail (mipmap)
//         gl.R8,               // internal format (one 8-bit channel)
//         auto_cast width,     // width
//         auto_cast height,    // height
//         auto_cast depth,     // depth
//         0,                   // border (must be 0)
//         gl.RED,              // format of the source data
//         gl.UNSIGNED_BYTE,    // data type of the source data (u8)
//         data,                // pointer to the data
//     );

//     // 4. Set texture parameters. For voxels, we want NEAREST filtering.
//     gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
//     gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
//     gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
//     gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
//     gl.TexParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);

//     // 5. Unbind the texture
//     gl.BindTexture(gl.TEXTURE_3D, 0);

//     return tex_id;
// }

// Creates the raw data. To be called by a WORKER THREAD.
// It does the slow work of filling the arrays and returns them.
chunk_create_raw_gpu_data :: proc(c: ^Chunk) -> (opacity_data, light_data: []u8) {
    // 1. Create data buffers in system memory
    opacity_data = make([]u8, CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)
    light_data   = make([]u8, CHUNK_SIZE_X * CHUNK_SIZE_Y * CHUNK_SIZE_Z)

    found_bright_spot := false
    // 2. Fill the buffers with chunk data
    i := 0
    for y in 0..<CHUNK_SIZE_Y {
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
                bt := c.blocks[y][z][x]
                if blocks.is_opaque(bt) {
                    opacity_data[i] = 255
                } else {
                    opacity_data[i] = 0
                }
                
                sky_l   := c.sky_light[y][z][x]
                block_l := c.block_light[y][z][x]
                
                light_val := max(sky_l, block_l)

                if !found_bright_spot && light_val > 10 {
                    found_bright_spot = true
                }
                light_data[i] = light_val * 17 // Scale 0-15 to 0-255
                i += 1
            }
        }
    }
    if found_bright_spot {
        fmt.printf("Chunk (%d, %d): OK - Found bright spots.\n", c.cx, c.cz)
    } else {
        fmt.printf("Chunk (%d, %d): ERROR - All light values are zero!\n", c.cx, c.cz)
    }
    // 3. Return the finished data. The worker will send this to the main thread.
    return
}

// Uploads the data. To be called by the MAIN THREAD.
// It takes the data prepared by the worker and performs the fast GPU upload.
chunk_upload_gpu_data :: proc(c: ^Chunk, opacity_data, light_data: []u8) {
    // 1. Unload old 3D textures if they exist, using our NEW function.
    chunk_unload_gpu_data(c)

    // 2. Create the new textures.
    c.opacity_tex_id = _create_voxel_texture_3d(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z, raw_data(opacity_data))
    c.light_tex_id   = _create_voxel_texture_3d(CHUNK_SIZE_X, CHUNK_SIZE_Y, CHUNK_SIZE_Z, raw_data(light_data))

    // 3. IMPORTANT: Free the memory for the slices.
    delete(opacity_data)
    delete(light_data)
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

chunk_unload_gpu_data :: proc(c: ^Chunk) {
    if c.opacity_tex_id != 0 {
        helpers.GL_DeleteTextures(1, &c.opacity_tex_id)
        c.opacity_tex_id = 0
    }
    if c.light_tex_id != 0 {
        helpers.GL_DeleteTextures(1, &c.light_tex_id)
        c.light_tex_id = 0
    }
}

get_chunk_aabb :: proc(c: ^Chunk) -> rl.BoundingBox {
	wx := f32(c.cx) * f32(CHUNK_SIZE_X)
	wz := f32(c.cz) * f32(CHUNK_SIZE_Z)
	min := rl.Vector3{wx, 0, wz}
	max := rl.Vector3{wx + f32(CHUNK_SIZE_X), f32(CHUNK_SIZE_Y), wz + f32(CHUNK_SIZE_Z)}
	return rl.BoundingBox{min, max}
}

// Given face f and its vertex corner "co", compute AO (0..1) and light (0..1)
sample_ao_and_light_for_corner :: proc(
    c: ^Chunk, bt: blocks.BlockType, x, y, z: int, f: int, co: rl.Vector3
) -> (ao: f32, light: f32) {
    // sign from corner coords
    sx: int; sy: int; sz: int
    if co.x > 0.5 { sx = 1 } else { sx = -1 }
    if co.y > 0.5 { sy = 1 } else { sy = -1 }
    if co.z > 0.5 { sz = 1 } else { sz = -1 }

    // tangent offsets B, C depend on face; N is face-normal (outside the block)
    offB := [3]int{0,0,0}
    offC := [3]int{0,0,0}
    offN := [3]int{ NEI[f][0], NEI[f][1], NEI[f][2] } // <- face normal (PX,NX,PY,NY,PZ,NZ)

    switch f {
    case 0, 1: // ±X -> tangents Y,Z
        offB = [3]int{0, sy, 0}
        offC = [3]int{0, 0, sz}
    case 2, 3: // ±Y -> tangents X,Z
        offB = [3]int{sx, 0, 0}
        offC = [3]int{0, 0, sz}
    case 4, 5: // ±Z -> tangents X,Y
        offB = [3]int{sx, 0, 0}
        offC = [3]int{0, sy, 0}
    }

    // ---------------- AO (classic 3-sample)
	occ :: proc(bt: blocks.BlockType) -> bool { return blocks.is_opaque(bt) }
	s1 := occ(get_block_world(c, x+offB[0],           y+offB[1],           z+offB[2]))
	s2 := occ(get_block_world(c, x+offC[0],           y+offC[1],           z+offC[2]))
	s3 := occ(get_block_world(c, x+offB[0]+offC[0],   y+offB[1]+offC[1],   z+offB[2]+offC[2]))

    ao_state := 3 - (int(s1) + int(s2) + int(s3))
    if s1 && s2 { ao_state = 0 }
    ao = AO_TABLE[ao_state]
    if bt == blocks.BlockType.Water { ao = 1.0 } // optional: no AO on water

	if f == 2 { // +Y face
		ao = ao + (1.0 - ao) * TOP_FACE_AO_BIAS
	}

    // ---------------- Light sampling (use face-outside cell + its two edges + corner)
    // Positions: N, N+B, N+C, N+B+C
    sx0 := get_sky_light_world(  c, x+offN[0],           y+offN[1],           z+offN[2]           )
    sx1 := get_sky_light_world(  c, x+offN[0]+offB[0],   y+offN[1]+offB[1],   z+offN[2]+offB[2]   )
    sx2 := get_sky_light_world(  c, x+offN[0]+offC[0],   y+offN[1]+offC[1],   z+offN[2]+offC[2]   )
    sx3 := get_sky_light_world(  c, x+offN[0]+offB[0]+offC[0], y+offN[1]+offB[1]+offC[1], z+offN[2]+offB[2]+offC[2] )

    bx0 := get_block_light_world( c, x+offN[0],           y+offN[1],           z+offN[2]           )
    bx1 := get_block_light_world( c, x+offN[0]+offB[0],   y+offN[1]+offB[1],   z+offN[2]+offB[2]   )
    bx2 := get_block_light_world( c, x+offN[0]+offC[0],   y+offN[1]+offC[1],   z+offN[2]+offC[2]   )
    bx3 := get_block_light_world( c, x+offN[0]+offB[0]+offC[0], y+offN[1]+offB[1]+offC[1], z+offN[2]+offB[2]+offC[2] )

    // Use max so missing neighbor chunks / solids don't crush sunlight
    sky  := f32(max(max(sx0, sx1), max(sx2, sx3)))
    bloc := f32(max(max(bx0, bx1), max(bx2, bx3)))
    l    := sky
    if bloc > l { l = bloc }

    light = l / f32(MAX_LIGHT)

	if light < MIN_LIGHT_BIAS { light = MIN_LIGHT_BIAS }
    if light > 1.0 { light = 1.0 }

	if bt == blocks.BlockType.Water && light < 0.35 {
		light = 0.35
	}

    return
}

build_skylight :: proc(c: ^Chunk) {
    for z in 0..<CHUNK_SIZE_Z {
        for x in 0..<CHUNK_SIZE_X {
            light := u8(15)
            for y := CHUNK_SIZE_Y-1; y >= 0; y -= 1 {
                bt := c.blocks[y][z][x]
                if blocks.is_opaque(bt) {
					light = 0
					c.sky_light[y][z][x] = 0
				} else {
					c.sky_light[y][z][x] = light
					// (optional) attenuate through air: if light > 0 do light -= 1
				}
                if y == 0 do break // Odin signed loop guard
            }
        }
    }
}

// Simple BFS flood for block lights inside the chunk (local-only first pass)
build_blocklight :: proc(c: ^Chunk) {
    // Zero it first
    for y in 0..<CHUNK_SIZE_Y {
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
                c.block_light[y][z][x] = 0
            }
        }
    }

    // Seed queue with emitters
    LightNode :: struct { x, y, z: i32, lvl: u8 }
    q: [dynamic]LightNode
    defer delete(q)

    for y in 0..<CHUNK_SIZE_Y {
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
                e := blocks.block_emission(c.blocks[y][z][x])
                if e > 0 {
                    c.block_light[y][z][x] = e
                    append(&q, LightNode{ cast(i32)x, cast(i32)y, cast(i32)z, e })
                }
            }
        }
    }

    // BFS
    qi := 0
    for qi < len(q) {
        n := q[qi]; qi += 1
        if n.lvl <= 1 do continue

        for d in 0..<6 {
            nx := n.x + cast(i32)NEI[d][0]
            ny := n.y + cast(i32)NEI[d][1]
            nz := n.z + cast(i32)NEI[d][2]

            if nx < 0 || nx >= CHUNK_SIZE_X ||
               ny < 0 || ny >= CHUNK_SIZE_Y ||
               nz < 0 || nz >= CHUNK_SIZE_Z { continue }

            nb := c.blocks[ny][nz][nx]
            if !blocks.can_light_through(nb) do continue

            nl := u8(n.lvl - 1)
            if c.block_light[ny][nz][nx] < nl {
                c.block_light[ny][nz][nx] = nl
                append(&q, LightNode{ x=nx, y=ny, z=nz, lvl=nl })
            }
        }
    }
}

// Convenience
chunk_rebuild_lighting :: proc(c: ^Chunk) {
    c.lights_ready = false
    build_skylight(c)
    build_blocklight(c)
    c.lights_ready = true
}

chunk_rebuild_lighting_neighbors :: proc(c: ^Chunk) {
    for dz in -1..=1 {
        for dx in -1..=1 {
            nb := world_get_chunk(c.world, c.cx+dx, c.cz+dz)
            if nb != nil {
                build_skylight(nb)
                build_blocklight(nb)
            }
        }
    }
}

// ───────────────── Meshing (Worker Thread) ─────────────────

// In chunk/Chunk.odin
chunk_build_geometry :: proc(c: ^Chunk) -> ^shared.MeshGeometry {
    geo := new(shared.MeshGeometry)
    
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
                        px := f32(c.cx*CHUNK_SIZE_X + x) + co.x
                        py := f32(y)                         + co.y
                        pz := f32(c.cz*CHUNK_SIZE_Z + z) + co.z

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
                    }

                    // Set the vertex color to the base tint.
                    base_col := face_tint(bt, cast(Face)f)
                    for _ in 0..<4 {
                        append(colorsP, base_col.r, base_col.g, base_col.b, base_col.a)
                    }

                    // Standard triangle indices
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

// If a geometry won't be uploaded (e.g. chunk died), free it here.
free_geometry :: proc(geo: ^shared.MeshGeometry) {
    if geo == nil do return
    delete(geo.vertsO); delete(geo.normsO); delete(geo.uvsO); delete(geo.colorsO); delete(geo.idxO)
    delete(geo.vertsW); delete(geo.normsW); delete(geo.uvsW); delete(geo.colorsW); delete(geo.idxW)
    free(geo)
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
    // Safeguard: Initial check before any work is done.
    if !sync.atomic_load(&c.alive) {
        return
    }

    heights: [CHUNK_SIZE_Z][CHUNK_SIZE_X]int

    // --- Pass 1: Heightmap, Stone, and Water (No changes here) ---
    for z in 0..<CHUNK_SIZE_Z {
        for x in 0..<CHUNK_SIZE_X {
            if !sync.atomic_load(&c.alive) { return }

            gx := c.cx*CHUNK_SIZE_X + x
            gz := c.cz*CHUNK_SIZE_Z + z
            nx := cast(f32)(gx) / params.scale
            nz := cast(f32)(gz) / params.scale

            hnoise := helpers.fbm2(noise, nx, nz, params.octaves, params.lacunarity, params.gain)
            height := params.sea_level + cast(int)(params.amplitude * hnoise)
            if height < 1 { height = 1 }
            if height > CHUNK_SIZE_Y-2 { height = CHUNK_SIZE_Y-2 }
            heights[z][x] = height

            for y in 0..<CHUNK_SIZE_Y {
                if y <= height {
                    c.blocks[y][z][x] = params.block_stone
                } else if params.use_water && y <= params.sea_level {
                    c.blocks[y][z][x] = params.block_water
                }
            }
        }
    }

    // --- Pass 2: Caves (No changes here) ---
    if params.caves {
        inv := 1.0 / params.cave_scale
        for z in 0..<CHUNK_SIZE_Z {
            for x in 0..<CHUNK_SIZE_X {
                top := heights[z][x]
                for y in 1..=top {
                    if (y & 15) == 0 && !sync.atomic_load(&c.alive) { return }

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
    
    // --- Pass 3: Topsoil (Changes are here) ---
    for z in 0..<CHUNK_SIZE_Z {
        for x in 0..<CHUNK_SIZE_X {
            if !sync.atomic_load(&c.alive) { return }

            // Find the true surface height after caves have been carved.
            surface_y := heights[z][x]
            for surface_y > 0 && c.blocks[surface_y][z][x] == blocks.BlockType.Air {
                surface_y -= 1
            }

            // Only place topsoil if the surface is stone.
            if c.blocks[surface_y][z][x] == params.block_stone {
                
                // NEW: Check if the block directly above the surface is water.
                is_underwater := false
                if surface_y + 1 < CHUNK_SIZE_Y { // A quick check to make sure we don't look out of bounds
                    if c.blocks[surface_y + 1][z][x] == params.block_water {
                        is_underwater = true
                    }
                }

                // NEW: Place dirt if underwater, otherwise place grass.
                if is_underwater {
                    // Tip: You could also add a 'block_sand' to your params for this case.
                    c.blocks[surface_y][z][x] = params.block_dirt 
                } else {
                    c.blocks[surface_y][z][x] = params.block_grass
                }

                // Place the dirt layer underneath (this logic remains the same).
                for d in 1..=params.top_soil {
                    dirt_y := surface_y - d
                    if dirt_y < 0 { break }
                    // Only replace stone with dirt.
                    if c.blocks[dirt_y][z][x] == params.block_stone {
                        c.blocks[dirt_y][z][x] = params.block_dirt
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
    // The world position of this chunk's origin (0,0,0)
    chunk_pos := rl.Vector3{f32(c.cx * CHUNK_SIZE_X), 0, f32(c.cz * CHUNK_SIZE_Z)};

    // Draw the model at its correct world position
    if c.model.meshCount > 0 { rl.DrawModel(c.model, chunk_pos, 1.0, rl.WHITE) }
    // (You can add the loop for models_opaque here too if you use it)
}

chunk_draw_water :: proc(c: ^Chunk) {
    // The world position of this chunk's origin (0,0,0)
    chunk_pos := rl.Vector3{f32(c.cx * CHUNK_SIZE_X), 0, f32(c.cz * CHUNK_SIZE_Z)};

    rl.BeginBlendMode(rl.BlendMode.ALPHA);
    rlgl.DisableDepthMask();
    // Draw the model at its correct world position
    if c.water_model.meshCount > 0 { rl.DrawModel(c.water_model, chunk_pos, 1.0, rl.WHITE) }
    rlgl.EnableDepthMask();
    rl.EndBlendMode();
}