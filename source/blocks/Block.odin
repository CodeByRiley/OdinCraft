package blocks

/// cell is a helper utility to convert a 2D (column, row) atlas coordinate
/// into a 1D linear index. Assumes a 16-column atlas.
cell :: proc(col, row: int) -> int { return row*16 + col }

/// Face represents the six cardinal directions of a cube's face.
/// PX = Positive X, NX = Negative X, etc.
Face :: enum u8 { PX, NX, PY, NY, PZ, NZ, Extra0, Extra1 }

/// UV2 represents a single 2D texture coordinate (U, V).
UV2    :: struct { u, v: f32 }

/// UVRect defines the bounding box of a texture within a larger atlas,
/// using normalized (0.0 to 1.0) coordinates.
UVRect :: struct {
	u0, v0, u1, v1: f32, // The min (u0,v0) and max (u1,v1) coordinates of the texture.
	textureIndex:   int,   // The original atlas cell index.
	frameCount:     int,   // For potential animation support.
	frameDuration:  f32,  // For potential animation support.
}

/// Block defines all the properties of a single type of block in the game.
Block :: struct {
	name:         cstring,    // The display name of the block.
	solid:        bool,       // If true, the block has collision and hides adjacent faces.
	gravity:      bool,       // If true, the block is affected by gravity (e.g., sand).
	opaque:       bool,       // If true, the block is rendered in the opaque pass. If false, it's transparent.
	produceLight: bool,       // If true, this block is a light source.
	uvs:          [8]UVRect,  // Pre-calculated UV rectangles for each of the 6 faces, plus 2 optional extras.
	type:         BlockType,  // The unique enum identifier for this block type.
	hardness:     f32,        // How long it takes to break the block.
	resistance:   f32,        // How well the block resists explosions.
	harvestLevel: int,        // The required tool level to harvest this block.
}

/// BlockOptions is a temporary "builder" struct used to conveniently define
/// a new block type before creating the final, immutable `Block` instance.
BlockOptions :: struct {
	name:         cstring,
	solid:        bool,
	gravity:      bool,
	opaque:       bool,
	produceLight: bool,
	uvs:          [8]UVRect,
	type:         BlockType,
	hardness:     f32,
	resistance:   f32,
	harvestLevel: int,
}

/// default_block_options is a helper to create a `BlockOptions` struct with common
/// default values for a standard, solid, opaque block.
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

/// create_block constructs a final `Block` from a `BlockOptions` descriptor.
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