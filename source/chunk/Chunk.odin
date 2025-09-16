package chunk

import "../blocks"
import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import mem "core:mem"
import "../helpers"

// ───────────────────────────── Config ─────────────────────────────
CHUNK_SIZE_X :: 32  // The width of a chunk in blocks.
CHUNK_SIZE_Z :: 32  // The depth of a chunk in blocks.
CHUNK_SIZE_Y :: 256 // The height of a chunk in blocks.

Face :: blocks.Face // Re-export the Face enum for convenience.

// ───────────────────────────── Types ─────────────────────────────

/// World is the top-level container for the entire game world. It holds a map
/// of all loaded chunks and global assets like the texture atlas.
World :: struct {
	chunks:    map[[2]int] ^Chunk, // A map from chunk coordinates [cx, cz] to a Chunk pointer.
	atlas:     blocks.Atlas,       // The atlas definition used for UV calculations.
	atlas_tex: rl.Texture2D,       // The actual GPU texture for the block atlas.
}

/// Chunk represents a vertical column of blocks (e.g., 32x256x32) in the world.
/// It contains the block data, its position, and the renderable mesh.
Chunk :: struct {
	blocks: [CHUNK_SIZE_X][CHUNK_SIZE_Z][CHUNK_SIZE_Y] blocks.BlockType, // 3D array of block IDs.
	cx, cz: int,      // The chunk's coordinates in the world grid.
	world:  ^World,   // A pointer back to the parent world.

	// GPU data for solid, opaque blocks.
	mesh:  rl.Mesh,
	model: rl.Model,

	// Separate GPU data for transparent blocks like water.
	water_mesh:  rl.Mesh,
	water_model: rl.Model,
	
	/// If true, the chunk's mesh needs to be rebuilt.
	dirty: bool,
}

// ───────────────────────────── Utils ─────────────────────────────

/// in_bounds checks if a given (x, y, z) coordinate is within the local bounds of a chunk.
in_bounds :: proc(x, y, z: int) -> bool {
	return x >= 0 && x < CHUNK_SIZE_X &&
	       y >= 0 && y < CHUNK_SIZE_Y &&
	       z >= 0 && z < CHUNK_SIZE_Z
}

/// make_rl_copy allocates memory using Raylib's internal allocator and copies the
/// contents of a slice into it. This is necessary for mesh data that will be
/// managed by Raylib's `UploadMesh` and `UnloadMesh` functions.
make_rl_copy :: proc($T: typeid, src: []T) -> ^T {
	n := len(src)
	if n == 0 do return nil
	total := cast(u32)(n * size_of(T))
	p := cast(^T) rl.MemAlloc(total)
	dst := mem.slice_ptr(p, n)
	for i in 0..<n do dst[i] = src[i]
	return p
}

/// FaceInfo stores the pre-calculated geometry for a single cube face.
FaceInfo :: struct {
	nrm:     rl.Vector3,   // The normal vector of the face.
	corners: [4]rl.Vector3, // The 4 corner vertices of the face, in counter-clockwise order.
}

// FACE_DATA is a lookup table containing the geometry for all 6 faces of a unit cube.
// Using this table is much faster than calculating the vertices and normals on the fly.
FACE_DATA := [6]FaceInfo{
	{ nrm = {+1,0,0}, corners = [4]rl.Vector3{{1,0,0},{1,1,0},{1,1,1},{1,0,1}} }, // Positive X
	{ nrm = {-1,0,0}, corners = [4]rl.Vector3{{0,0,1},{0,1,1},{0,1,0},{0,0,0}} }, // Negative X
	{ nrm = {0,+1,0}, corners = [4]rl.Vector3{{0,1,1},{1,1,1},{1,1,0},{0,1,0}} }, // Positive Y (Top)
	{ nrm = {0,-1,0}, corners = [4]rl.Vector3{{0,0,0},{1,0,0},{1,0,1},{0,0,1}} }, // Negative Y (Bottom)
	{ nrm = {0,0,+1}, corners = [4]rl.Vector3{{0,0,1},{1,0,1},{1,1,1},{0,1,1}} }, // Positive Z
	{ nrm = {0,0,-1}, corners = [4]rl.Vector3{{1,0,0},{0,0,0},{0,1,0},{1,1,0}} }, // Negative Z
}

// NEI is a lookup table of the 6 neighbor block offsets, used for face culling.
NEI := [6][3]int{
	{+1,0,0},{-1,0,0}, // Right, Left
	{0,+1,0},{0,-1,0}, // Top, Bottom
	{0,0,+1},{0,0,-1}, // Front, Back
}

// Pre-defined vertex colors used to tint certain textures.
GRASS_TINT  := rl.Color{118,182,76,255}
LEAVES_TINT := rl.Color{127,178,56,255}
WATER_TINT  := rl.Color{63,118,228,180} // Note the lower alpha for transparency.

/// face_tint returns a specific color for certain block faces (e.g., green for grass tops)
/// or returns white (no tint) for all other blocks.
face_tint :: proc(bt: blocks.BlockType, face: Face) -> rl.Color {
	if bt == blocks.BlockType.Grass && face == Face.PY {
		return GRASS_TINT
	}
	if bt == blocks.BlockType.OakLeaves do return LEAVES_TINT
	if bt == blocks.BlockType.Water     do return WATER_TINT
	return rl.WHITE // Default: no tint.
}

// ───────────────────────────── World API ─────────────────────────
/// world_init initializes a new World struct.
world_init :: proc(w: ^World, inset_px: f32 = 0.0) {
	w.chunks = make(map[[2]int] ^Chunk)
	w.atlas  = blocks.atlas_make(inset_px)
}

/// world_add_chunk adds a chunk to the world's chunk map and sets its parent world pointer.
world_add_chunk :: proc(w: ^World, c: ^Chunk) {
	w.chunks[[2]int{c.cx, c.cz}] = c
	c.world = w
}

/// world_get_chunk safely retrieves a chunk from the world map at the given chunk coordinates.
/// Returns nil if the chunk is not loaded.
world_get_chunk :: proc(w: ^World, cx, cz: int) -> ^Chunk {
	if w == nil do return nil
	if c, ok := w.chunks[[2]int{cx, cz}]; ok { return c }
	return nil
}

/// world_set_atlas_texture assigns the GPU texture to the world and applies
/// recommended texture filtering for pixel art.
world_set_atlas_texture :: proc(w: ^World, tex: rl.Texture2D) {
	w.atlas_tex = tex
	rl.SetTextureFilter(tex, rl.TextureFilter.POINT)
}

// ───────────────────────────── Chunk API ─────────────────────────
/// chunk_init initializes a new Chunk at the given chunk coordinates,
/// setting its block data to Air by default.
chunk_init :: proc(c: ^Chunk, cx, cz: int) {
	c.cx = cx; c.cz = cz
	c.dirty = true
	c.mesh  = rl.Mesh{}
	c.model = rl.Model{}

	// Ensure new chunks start empty to avoid a "shell" of default blocks.
	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			for y in 0..<CHUNK_SIZE_Y {
				c.blocks[x][z][y] = blocks.BlockType.Air
			}
		}
	}
}

/// chunk_set places a block of a given type at the specified local coordinates
/// within the chunk and marks the chunk as dirty.
chunk_set :: proc(c: ^Chunk, x, y, z: int, bt: blocks.BlockType) {
	if !in_bounds(x,y,z) do return
	c.blocks[x][z][y] = bt
	c.dirty = true
}

/// chunk_get retrieves the block type at the specified local coordinates.
/// Returns Air if the coordinates are out of bounds.
chunk_get :: proc(c: ^Chunk, x, y, z: int) -> blocks.BlockType {
	if !in_bounds(x,y,z) do return blocks.BlockType.Air
	return c.blocks[x][z][y]
}

/// chunk_set_layer sets an entire horizontal layer of a chunk to a specific block type.
chunk_set_layer :: proc(c: ^Chunk, y: int, bt: blocks.BlockType) {
	if y < 0 || y >= CHUNK_SIZE_Y { return }
	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			c.blocks[x][z][y] = bt
		}
	}
	c.dirty = true
}

/// chunk_fill_to_height fills a chunk with a block type from Y=0 up to and including H.
chunk_fill_to_height :: proc(c: ^Chunk, h: int, bt: blocks.BlockType) {
	// Clamp height to be within chunk bounds.
	H := h
	if H < 0           { H = 0 }
	if H >= CHUNK_SIZE_Y { H = CHUNK_SIZE_Y - 1 }

	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			for y in 0..=H {
				c.blocks[x][z][y] = bt
			}
		}
	}
	c.dirty = true
}

/// get_block_world safely retrieves a block at local chunk coordinates. If the coordinates
/// are outside the current chunk, it calculates the correct neighbor chunk and samples from it.
/// Returns Air if the neighbor chunk isn't loaded.
get_block_world :: proc(c: ^Chunk, lx, ly, lz: int) -> blocks.BlockType {
	// Fast path for blocks within the current chunk.
	if in_bounds(lx,ly,lz) do return c.blocks[lx][lz][ly]
	// Fast path for out-of-bounds Y coordinates.
	if ly < 0 || ly >= CHUNK_SIZE_Y do return blocks.BlockType.Air

	// Calculate the neighbor chunk coordinates (nx, nz) and the new local coordinates (gx, gz).
	nx := c.cx; nz := c.cz
	gx := lx;   gz := lz
	for gx < 0           { gx += CHUNK_SIZE_X; nx -= 1 }
	for gx >= CHUNK_SIZE_X { gx -= CHUNK_SIZE_X; nx += 1 }
	for gz < 0           { gz += CHUNK_SIZE_Z; nz -= 1 }
	for gz >= CHUNK_SIZE_Z { gz -= CHUNK_SIZE_Z; nz += 1 }

	// Get the neighbor chunk from the world.
	nbor := world_get_chunk(c.world, nx, nz)
	if nbor == nil do return blocks.BlockType.Air // If neighbor isn't loaded, treat it as air.
	return nbor.blocks[gx][gz][ly]
}

/// is_solid is a helper for the culling algorithm, defining which block types hide adjacent faces.
is_solid :: proc(bt: blocks.BlockType) -> bool {
	// Water is not solid, so solid blocks will be visible through it.
	return bt != blocks.BlockType.Air &&
	       bt != blocks.BlockType.Water
}

/// get_uv_for is a convenience wrapper to get the UV coordinates for a specific block face.
get_uv_for :: proc(atlas: ^blocks.Atlas, bt: blocks.BlockType, face: Face) -> (u0,v0,u1,v1: f32) {
	cell := blocks.tile_for_face(bt, face)
	r    := blocks.atlas_uv_rect(atlas, cell)
	return r.u0, r.v0, r.u1, r.v1
}

/// chunk_unload_gpu frees any GPU memory (Meshes and Models) associated with this chunk.
/// This must be called before rebuilding a mesh to prevent memory leaks.
chunk_unload_gpu :: proc(c: ^Chunk) {
	if c.model.meshCount > 0 { rl.UnloadModel(c.model); c.model = rl.Model{} }
	if c.mesh.vertexCount > 0 { rl.UnloadMesh(c.mesh); c.mesh = rl.Mesh{} }

	if c.water_model.meshCount > 0 { rl.UnloadModel(c.water_model); c.water_model = rl.Model{} }
	if c.water_mesh.vertexCount > 0 { rl.UnloadMesh(c.water_mesh); c.water_mesh = rl.Mesh{} }    
}

/// get_chunk_aabb calculates the world-space Axis-Aligned Bounding Box for this chunk.
/// Used for frustum culling.
get_chunk_aabb :: proc(c: ^Chunk) -> rl.BoundingBox {
	wx := f32(c.cx) * f32(CHUNK_SIZE_X)
	wz := f32(c.cz) * f32(CHUNK_SIZE_Z)

	min := rl.Vector3{wx, 0, wz}
	max := rl.Vector3{
		wx + f32(CHUNK_SIZE_X), 
		f32(CHUNK_SIZE_Y), 
		wz + f32(CHUNK_SIZE_Z), // Corrected from CHUNK_SIZE_X
	}

	return rl.BoundingBox{min, max}
}

/// chunk_update_mesh rebuilds the chunk's renderable mesh from its block data if it is marked as 'dirty'.
/// This is the most performance-critical part of the chunk system.
chunk_update_mesh :: proc(c: ^Chunk) {
	if !c.dirty do return // Don't rebuild if nothing has changed.
	c.dirty = false

	// Create dynamic arrays to hold the geometry for opaque and water meshes separately.
	vertsO: [dynamic]f32; normsO: [dynamic]f32
	uvsO:   [dynamic]f32; colorsO: [dynamic]u8
	idxO:   [dynamic]u16
	vertsW: [dynamic]f32; normsW: [dynamic]f32
	uvsW:   [dynamic]f32; colorsW: [dynamic]u8
	idxW:   [dynamic]u16

	// Iterate over every block in the chunk.
	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			for y in 0..<CHUNK_SIZE_Y {
				bt := c.blocks[x][z][y]
				if bt == blocks.BlockType.Air do continue // Skip air blocks.

				is_water_tile := (bt == blocks.BlockType.Water)

				// Check all 6 faces of the block.
				for f in 0..<6 {
					// Get the coordinates of the neighboring block.
					nx := x + NEI[f][0]
					ny := y + NEI[f][1]
					nz := z + NEI[f][2]
					nb := get_block_world(c, nx, ny, nz)

					// This is "greedy meshing" or face culling. A face is only visible (and thus meshed)
					// if it is adjacent to a non-solid block (like air or water).
					if !is_water_tile {
						// Opaque blocks are hidden by any solid block.
						if is_solid(nb) do continue
					} else {
						// Water faces are only hidden by other water blocks.
						if nb == blocks.BlockType.Water do continue
					}

					// Choose which set of buffers (Opaque or Water) to add this face's geometry to.
					vertsP := &vertsO; normsP := &normsO; uvsP := &uvsO; colsP := &colorsO; idxP := &idxO
					if is_water_tile {
						vertsP = &vertsW; normsP = &normsW; uvsP = &uvsW; colsP = &colorsW; idxP = &idxW
					}

					face := FACE_DATA[f]
					base := cast(u16)(len(vertsP^) / 3) // Base index for the new vertices.

					u0, v0, u1, v1 := get_uv_for(&c.world.atlas, bt, cast(Face)f)

					// Add the 4 vertices for this face.
					for k in 0..<4 {
						co := face.corners[k]

						// Calculate world position of the vertex.
						px := cast(f32)(c.cx*CHUNK_SIZE_X + x) + co.x
						py := cast(f32)(y)                    + co.y
						pz := cast(f32)(c.cz*CHUNK_SIZE_Z + z) + co.z
						append(vertsP, px); append(vertsP, py); append(vertsP, pz)

						// Add the normal vector (same for all 4 vertices of a flat face).
						append(normsP, face.nrm.x); append(normsP, face.nrm.y); append(normsP, face.nrm.z)

						// Calculate texture coordinates (UVs) for this vertex.
						s, t: f32
						switch f {
						case 0: s = co.z;        t = 1.0 - co.y
						case 1: s = 1.0 - co.z;  t = 1.0 - co.y
						case 2: s = co.x;        t = co.z
						case 3: s = co.x;        t = 1.0 - co.z
						case 4: s = 1.0 - co.x;  t = 1.0 - co.y
						case 5: s = co.x;        t = 1.0 - co.y
						}

						// Map the 0-1 texture coordinate to the specific rectangle in the atlas.
						u := u0 + (u1 - u0)*s
						v := v0 + (v1 - v0)*t
						append(uvsP, u); append(uvsP, v)

						// Add vertex color for tinting.
						col := face_tint(bt, cast(Face)f)
						append(colsP, col.r); append(colsP, col.g); append(colsP, col.b); append(colsP, col.a)
					}

					// Add indices to form two triangles for the quad face.
					append(idxP, base+0); append(idxP, base+1); append(idxP, base+2)
					append(idxP, base+0); append(idxP, base+2); append(idxP, base+3)
				}
			}
		}
	}

	// Before creating new GPU resources, free the old ones.
	chunk_unload_gpu(c)

	// Upload the generated opaque mesh data to the GPU.
	if len(idxO) > 0 {
		c.mesh.vertexCount   = cast(i32)(len(vertsO)/3)
		c.mesh.triangleCount = cast(i32)(len(idxO)/3)
		c.mesh.vertices    = make_rl_copy(f32, vertsO[:])
		c.mesh.normals     = make_rl_copy(f32, normsO[:])
		c.mesh.texcoords   = make_rl_copy(f32, uvsO[:])
		c.mesh.colors      = make_rl_copy(u8,  colorsO[:])
		c.mesh.indices     = make_rl_copy(u16, idxO[:])
		rl.UploadMesh(&c.mesh, true) // `true` makes it dynamic for potential future updates.
		c.model = rl.LoadModelFromMesh(c.mesh)
		if c.world != nil && c.world.atlas_tex.id != 0 {
			rl.SetMaterialTexture(&c.model.materials[0], rl.MaterialMapIndex.ALBEDO, c.world.atlas_tex)
		}
	}

	// Upload the generated water mesh data to the GPU.
	if len(idxW) > 0 {
		c.water_mesh.vertexCount   = cast(i32)(len(vertsW)/3)
		c.water_mesh.triangleCount = cast(i32)(len(idxW)/3)
		c.water_mesh.vertices    = make_rl_copy(f32, vertsW[:])
		c.water_mesh.normals     = make_rl_copy(f32, normsW[:])
		c.water_mesh.texcoords   = make_rl_copy(f32, uvsW[:])
		c.water_mesh.colors      = make_rl_copy(u8,  colorsW[:])
		c.water_mesh.indices     = make_rl_copy(u16, idxW[:])
		rl.UploadMesh(&c.water_mesh, true)
		c.water_model = rl.LoadModelFromMesh(c.water_mesh)
		if c.world != nil && c.world.atlas_tex.id != 0 {
			rl.SetMaterialTexture(&c.water_model.materials[0], rl.MaterialMapIndex.ALBEDO, c.world.atlas_tex)
		}
	}
}


/// TerrainParams holds all the configurable parameters for procedural world generation.
TerrainParams :: struct {
	// Heightmap parameters
	scale:       f32, // Controls the "zoom" of the terrain noise. Larger values = more stretched out terrain.
	octaves:     int, // Number of noise layers to combine for detail.
	lacunarity:  f32, // Frequency multiplier for each subsequent octave.
	gain:        f32, // Amplitude multiplier for each subsequent octave.
	amplitude:   f32, // The maximum vertical variation of the terrain in blocks.
	sea_level:   int, // The Y-level at which water appears.
	top_soil:    int, // The depth of dirt that appears under grass blocks.

	// Cave generation parameters
	caves:           bool,
	cave_scale:      f32, // Controls the size of the caves.
	cave_octaves:    int,
	cave_lacunarity: f32,
	cave_gain:       f32,
	cave_threshold:  f32, // The noise value above which caves are carved out.

	// Block types to use during generation
	block_stone:  blocks.BlockType,
	block_dirt:   blocks.BlockType,
	block_grass:  blocks.BlockType,
	use_water:    bool,
	block_water:  blocks.BlockType,
}

/// default_terrain_params provides a good starting set of parameters for generating interesting terrain.
default_terrain_params :: proc() -> TerrainParams {
	return TerrainParams{
		scale       = 128.0,
		octaves     = 5,
		lacunarity  = 2.0,
		gain        = 0.5,
		amplitude   = 40.0,
		sea_level   = 62,
		top_soil    = 3,

		caves           = true,
		cave_scale      = 96.0,
		cave_octaves    = 3,
		cave_lacunarity = 2.0,
		cave_gain       = 0.5,
		cave_threshold  = 0.55,

		block_stone = blocks.BlockType.Stone,
		block_dirt  = blocks.BlockType.Dirt,
		block_grass = blocks.BlockType.Grass,
		use_water   = false,
		block_water = blocks.BlockType.Water,
	}
}

// ───────────────────────────── Chunk generation ─────────────────────────────

/// chunk_generate_perlin fills a chunk's block data using multi-layered Perlin noise (fBm).
/// It creates a heightmap-based terrain with stone, dirt, grass, optional water, and optional caves.
chunk_generate_perlin :: proc(c: ^Chunk, noise: ^helpers.Perlin, seed: u32, params: TerrainParams) {
	// Start with a completely empty chunk.
	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			for y in 0..<CHUNK_SIZE_Y {
				c.blocks[x][z][y] = blocks.BlockType.Air
			}
		}
	}

	// Pre-calculate the height of the terrain at each (x, z) column.
	heights: [CHUNK_SIZE_X][CHUNK_SIZE_Z]int
	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			// Convert local chunk coordinates to global world coordinates for seamless noise.
			gx := c.cx*CHUNK_SIZE_X + x
			gz := c.cz*CHUNK_SIZE_Z + z
			nx := cast(f32)(gx) / params.scale
			nz := cast(f32)(gz) / params.scale

			// Generate 2D fractal noise for the heightmap.
			hnoise := helpers.fbm2(noise, nx, nz, params.octaves, params.lacunarity, params.gain) // Result is ~[-1,1]
			// Map the noise value to a world height centered around the sea level.
			height := params.sea_level + cast(int)(params.amplitude * hnoise)
			if height < 1 { height = 1 }
			if height > CHUNK_SIZE_Y-2 { height = CHUNK_SIZE_Y-2 }
			heights[x][z] = height

			// Fill everything from Y=0 up to the calculated height with stone.
			for y in 0..=height {
				c.blocks[x][z][y] = params.block_stone
			}

			// If the terrain is below sea level, fill the space up to sea level with water.
			if params.use_water && params.sea_level > height {
				for y in height+1 ..= params.sea_level {
					if y >= 0 && y < CHUNK_SIZE_Y {
						c.blocks[x][z][y] = params.block_water
					}
				}
			}
		}
	}

	// Second pass: Carve out caves using 3D Perlin noise.
	if params.caves {
		inv := 1.0 / params.cave_scale
		for x in 0..<CHUNK_SIZE_X {
			for z in 0..<CHUNK_SIZE_Z {
				top := heights[x][z]
				for y in 1..=top { // Iterate from Y=1 to the surface, leaving a bedrock layer at Y=0.
					nx := cast(f32)(c.cx*CHUNK_SIZE_X + x) * inv
					ny := cast(f32)(y)                    * inv
					nz := cast(f32)(c.cz*CHUNK_SIZE_Z + z) * inv
					n3 := helpers.fbm3(noise, nx, ny, nz, params.cave_octaves, params.cave_lacunarity, params.cave_gain)
					// If the 3D noise value is above a threshold, carve out the block (set to Air).
					if n3 > params.cave_threshold {
						c.blocks[x][z][y] = blocks.BlockType.Air
					}
				}
			}
		}
	}

	// Third pass: Place topsoil (dirt and grass).
	for x in 0..<CHUNK_SIZE_X {
		for z in 0..<CHUNK_SIZE_Z {
			// Find the actual surface block after caves have been carved.
			y := heights[x][z]
			for y >= 1 {
				if c.blocks[x][z][y] != blocks.BlockType.Air do break
				y -= 1
			}
			if y < 1 do continue // Skip if the column is empty.

			// Place a grass block on the surface.
			c.blocks[x][z][y] = params.block_grass

			// Place dirt blocks for a few layers underneath the grass.
			for d in 1..=params.top_soil {
				yy := y - d
				if yy <= 0 do break
				// Only replace stone with dirt. Don't fill in caves.
				if c.blocks[x][z][yy] == params.block_stone {
					c.blocks[x][z][yy] = params.block_dirt
				}
			}
		}
	}

	c.dirty = true // Mark the chunk for remeshing.
}

/// chunk_draw_opaque renders the chunk's main solid model.
chunk_draw_opaque :: proc(c: ^Chunk) {
	if c != nil && c.model.meshCount > 0 {
		rl.DrawModel(c.model, rl.Vector3{0,0,0}, 1.0, rl.WHITE)
	}
}

/// chunk_draw_water renders the chunk's transparent water model.
/// It correctly sets the blend mode and disables depth writing for proper transparency.
chunk_draw_water :: proc(c: ^Chunk) {
	if c != nil && c.water_model.meshCount > 0 {
		rl.BeginBlendMode(rl.BlendMode.ALPHA)
		rlgl.DisableDepthMask() // Allow objects behind the water to be seen (depth test ON, depth write OFF).
		rl.DrawModel(c.water_model, rl.Vector3{0,0,0}, 1.0, rl.WHITE)
		rlgl.EnableDepthMask()  // Re-enable depth writing for subsequent opaque objects.
		rl.EndBlendMode()
	}
}