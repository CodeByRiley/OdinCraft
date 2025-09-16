package blocks

import mem "core:mem"

Atlas :: struct {
	tex_w, tex_h: f32, // The total width and height of the atlas texture in pixels (e.g., 256x256).
	tile_w, tile_h: f32, // The width and height of a single tile in pixels (e.g., 16x16).
	cols, rows:   int, // The number of columns and rows of tiles in the atlas.
	inset_px:     f32, // A small pixel inset to prevent "texture bleeding" when using LINEAR filtering. 0.0 is fine for POINT filtering.
}

/// atlas_make creates a new Atlas instance with predefined dimensions for the texture.
atlas_make :: proc(inset_px: f32) -> Atlas {
	return Atlas{
		tex_w = 256,  tex_h = 256,
		tile_w = 16,  tile_h = 16,
		cols = 16,    rows = 16,
		inset_px = inset_px,
	}
}

/// atlas_uv_rect calculates the normalized texture coordinates (UVs) for a specific tile
/// within the atlas, identified by its linear cell index.
atlas_uv_rect :: proc(a: ^Atlas, cell_index: int) -> UVRect {
	// Convert the linear index back to a 2D column and row.
	cx := cell_index % a.cols
	cy := cell_index / a.cols

	// Calculate the top-left (u0, v0) and bottom-right (u1, v1) UV coordinates.
	// These are normalized from 0.0 to 1.0.
	u0 := (cast(f32)cx * a.tile_w + a.inset_px) / a.tex_w
	v0 := (cast(f32)cy * a.tile_h + a.inset_px) / a.tex_h
	u1 := ((cast(f32)cx + 1) * a.tile_w - a.inset_px) / a.tex_w
	v1 := ((cast(f32)cy + 1) * a.tile_h - a.inset_px) / a.tex_h

	return UVRect{
		u0 = u0, v0 = v0, u1 = u1, v1 = v1,
		textureIndex = cell_index,
		frameCount = 1, frameDuration = 0, // Fields for potential animation support.
	}
}

/// tile_for_face returns the correct atlas cell index for a specific face of a given block type.
/// This allows blocks like Grass to have different textures on their top, sides, and bottom.
/// By default, it returns the block's type enum value, assuming a 1-to-1 mapping in the atlas.
tile_for_face :: proc(b: BlockType, f: Face) -> int {
	// Special case for Grass blocks.
	if b == .Grass {
		// Define the atlas cell indices for the different grass faces.
		grass_top    := cell( 0, 0 ) // Example: top texture is at column 0, row 0.
		grass_bottom := cell( 2, 0 ) // Dirt texture.
		grass_side   := cell( 3, 0 )

		// Return the correct index based on which face is being requested.
		if f == .PY do return grass_top    // Positive Y is the top face.
		if f == .NY do return grass_bottom // Negative Y is the bottom face.
		return grass_side                  // All other faces (sides) use the side texture.
	}

	// For all other blocks, the cell index is the same as the block type's integer value.
	return cast(int)b
}


/// gen_block_uvs builds the complete set of 8 UVRects for a block type.
/// It iterates through the 6 main faces, determines the correct texture for each,
/// and calculates its UV coordinates in the atlas.
gen_block_uvs :: proc(a: ^Atlas, b: BlockType) -> [8]UVRect {
	out: [8]UVRect // Zero-initialized, mutable by default.

	// Use a half-open range 0..<6 to cover the 6 main faces.
	for face in 0..<6 {
		// Get the specific atlas cell for this block face (e.g., grass top vs. grass side).
		cell := tile_for_face(b, cast(Face)face)
		// Calculate the UV rectangle for that cell and store it.
		out[face] = atlas_uv_rect(a, cell)
	}

	return out
}


/// get_defaults creates and returns a slice containing the default block definitions for the game.
/// This function allocates the slice on the heap using the provided allocator.
get_defaults :: proc(allocator: mem.Allocator) -> []Block {
	atlas := atlas_make(0.0) // Create a default atlas helper.

	// Allocate the slice that will hold all our block definitions.
	blocks := make([]Block, 2, allocator=allocator)

	// Define the properties for each block.
	blocks[0] = create_block(default_block_options("Stone", gen_block_uvs(&atlas, .Stone), .Stone, 1.5, 10.0, 1))
	blocks[1] = create_block(default_block_options("Dirt",  gen_block_uvs(&atlas, .Dirt),  .Dirt,  1.0,  2.0,  1))

	return blocks // It's safe to return this slice because it's backed by heap memory.
}