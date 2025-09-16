package helpers

import math "core:math"

// ───────────────────────────── Perlin noise ─────────────────────────────

/// Perlin holds the state for a Perlin noise generator.
/// Its primary component is a permutation table, which is a randomized array of values
/// used to generate pseudo-random gradients at integer grid points.
Perlin :: struct {
	perm: [512]u8,
}

/// perlin_init initializes the Perlin noise generator with a given seed.
/// It creates and shuffles a permutation table based on the seed.
perlin_init :: proc(n: ^Perlin, seed: u32) {
	// 1. Create an ordered array from 0 to 255.
	tmp: [256]u8
	for i in 0..<256 {
		tmp[i] = cast(u8)i
	}

	// 2. Shuffle the array pseudo-randomly using the Fisher–Yates algorithm.
	// A simple Linear Congruential Generator (LCG) is used for the random numbers.
	s: u32 = seed | 1 // Ensure seed is not zero.
	for i := 255; i > 0; i -= 1 {
		// Generate the next pseudo-random number.
		s = s*cast(u32)(1664525) + cast(u32)(1013904223)
		// Pick an index j from 0 to i.
		j := cast(int)(s % cast(u32)(i+1))
		// Swap the elements at i and j.
		t := tmp[i]
		tmp[i] = tmp[j]
		tmp[j] = t
	}

	// 3. Duplicate the shuffled array into the 512-element permutation table.
	// This is a clever optimization that avoids expensive modulo operations later.
	// By having perm[i] == perm[i+256], we can use simple bitwise ANDs for wrapping.
	for i in 0..<256 {
		n.perm[i]     = tmp[i]
		n.perm[i+256] = tmp[i]
	}
}

/// perlin_fade is Ken Perlin's "smootherstep" function (6t^5 - 15t^4 + 10t^3).
/// It creates an ease-in, ease-out curve which is used for interpolation. This is crucial
/// for eliminating grid-like artifacts that would be visible with simple linear interpolation.
perlin_fade :: proc(t: f32) -> f32 {
	return t*t*t*(t*(t*6 - 15) + 10)
}

/// perlin_lerp performs linear interpolation between two values 'a' and 'b' by a factor 't'.
perlin_lerp :: proc(a, b, t: f32) -> f32 {
	return a + t*(b - a)
}

/// perlin_grad2 selects one of 8 pseudo-random 2D gradient vectors based on a hash value 'h'
/// and computes the dot product with the given vector (x, y).
perlin_grad2 :: proc(h: u8, x, y: f32) -> f32 {
	hh := cast(int)h & 7 // Limit hash to 0-7 for 8 directions.
	u: f32
	v: f32
	if (hh & 1) == 0 { u = x } else { u = -x }
	if (hh & 2) == 0 { v = y } else { v = -y }
	return u + v
}

/// perlin2 calculates the 2D Perlin noise value for a given (x, y) coordinate.
/// The result is a continuous value approximately in the range [-1, 1].
perlin2 :: proc(n: ^Perlin, x, y: f32) -> f32 {
	// 1. Find the integer coordinates of the grid cell the point is in (Xi, Yi).
	// The bitwise AND with 255 ensures the coordinates wrap around, making the noise tileable.
	Xi := (cast(int)math.floor(x)) & 255
	Yi := (cast(int)math.floor(y)) & 255
	// Find the fractional coordinates of the point within that cell (xf, yf).
	xf := x - math.floor(x)
	yf := y - math.floor(y)

	// 2. Apply the fade function to the fractional coordinates to get smooth interpolation weights.
	u := perlin_fade(xf)
	v := perlin_fade(yf)

	// 3. Compute hash values for the four corner points of the grid cell using the permutation table.
	A  := n.perm[Xi] + cast(u8)(Yi)
	AA := n.perm[cast(int)(A)]    // Top-left corner hash.
	AB := n.perm[cast(int)(A) + 1] // Bottom-left corner hash.
	B  := n.perm[(Xi+1) & 255] + cast(u8)(Yi)
	BA := n.perm[cast(int)(B)]    // Top-right corner hash.
	BB := n.perm[cast(int)(B) + 1] // Bottom-right corner hash.

	// 4. Calculate the influence of each corner's gradient on the sample point.
	// Then, interpolate these influences along the X-axis.
	x1 := perlin_lerp(perlin_grad2(AA, xf,   yf),
	                  perlin_grad2(BA, xf-1, yf), u)

	x2 := perlin_lerp(perlin_grad2(AB, xf,   yf-1),
	                  perlin_grad2(BB, xf-1, yf-1), u)

	// 5. Interpolate the results from the previous step along the Y-axis to get the final noise value.
	return perlin_lerp(x1, x2, v)
}

// A lookup table of 12 gradient vectors pointing to the edges of a cube. Used for 3D noise.
GRAD3 := [12][3]f32{
	{+1,+1,0}, {-1,+1,0}, {+1,-1,0}, {-1,-1,0},
	{+1,0,+1}, {-1,0,+1}, {+1,0,-1}, {-1,0,-1},
	{0,+1,+1}, {0,-1,+1}, {0,+1,-1}, {0,-1,-1},
}

/// perlin_grad3 selects one of the 12 pseudo-random 3D gradient vectors from the GRAD3 table
/// and computes the dot product with the given vector (x, y, z).
perlin_grad3 :: proc(h: u8, x, y, z: f32) -> f32 {
	g := GRAD3[cast(int)(h % 12)]
	return g[0]*x + g[1]*y + g[2]*z
}

/// perlin3 calculates the 3D Perlin noise value for a given (x, y, z) coordinate.
perlin3 :: proc(n: ^Perlin, x, y, z: f32) -> f32 {
	// 1. Find the integer coordinates of the grid cube the point is in.
	Xi := (cast(int)math.floor(x)) & 255
	Yi := (cast(int)math.floor(y)) & 255
	Zi := (cast(int)math.floor(z)) & 255
	// Find the fractional coordinates within that cube.
	xf := x - math.floor(x)
	yf := y - math.floor(y)
	zf := z - math.floor(z)

	// 2. Apply the fade function to get smooth interpolation weights.
	u := perlin_fade(xf)
	v := perlin_fade(yf)
	w := perlin_fade(zf)

	// 3. Compute hash values for the eight corner points of the grid cube.
	A  := n.perm[Xi] + cast(u8)(Yi)
	AA := n.perm[cast(int)(A)]     + cast(u8)(Zi)
	AB := n.perm[cast(int)(A) + 1] + cast(u8)(Zi)
	B  := n.perm[(Xi+1) & 255] + cast(u8)(Yi)
	BA := n.perm[cast(int)(B)]     + cast(u8)(Zi)
	BB := n.perm[cast(int)(B) + 1] + cast(u8)(Zi)

	// 4. Perform trilinear interpolation. This involves 7 lerp operations.
	// First, interpolate along the X-axis for the 4 front edges.
	x1 := perlin_lerp(perlin_grad3(n.perm[cast(int)(AA)], xf,   yf,   zf),
	                  perlin_grad3(n.perm[cast(int)(BA)], xf-1, yf,   zf), u)
	x2 := perlin_lerp(perlin_grad3(n.perm[cast(int)(AB)], xf,   yf-1, zf),
	                  perlin_grad3(n.perm[cast(int)(BB)], xf-1, yf-1, zf), u)
	// Then, interpolate the results of the front edges along the Y-axis.
	y1 := perlin_lerp(x1, x2, v)

	// Repeat for the 4 back edges.
	x3 := perlin_lerp(perlin_grad3(n.perm[cast(int)(AA) + 1], xf,   yf,   zf-1),
	                  perlin_grad3(n.perm[cast(int)(BA) + 1], xf-1, yf,   zf-1), u)
	x4 := perlin_lerp(perlin_grad3(n.perm[cast(int)(AB) + 1], xf,   yf-1, zf-1),
	                  perlin_grad3(n.perm[cast(int)(BB) + 1], xf-1, yf-1, zf-1), u)
	// Interpolate the results of the back edges along the Y-axis.
	y2 := perlin_lerp(x3, x4, v)

	// Finally, interpolate between the front face result (y1) and back face result (y2) along the Z-axis.
	return perlin_lerp(y1, y2, w)
}

/// fbm2 calculates 2D Fractal Brownian Motion by summing multiple layers (octaves) of Perlin noise.
/// This creates a more detailed and natural-looking result than a single noise call.
/// `lacunarity`: Controls the frequency increase for each octave (typically 2.0).
/// `gain`: Controls the amplitude decrease for each octave (typically 0.5).
fbm2 :: proc(n: ^Perlin, x, y: f32, octaves: int, lacunarity, gain: f32) -> f32 {
	sum: f32 = 0
	amp: f32 = 0.5
	freq: f32 = 1
	for _ in 0..<octaves {
		// Add a layer of noise, scaled by the current amplitude.
		sum  += perlin2(n, x*freq, y*freq) * amp
		// Increase the frequency and decrease the amplitude for the next octave.
		freq *= lacunarity
		amp  *= gain
	}
	return sum
}

/// fbm3 calculates 3D Fractal Brownian Motion. See fbm2 for details.
fbm3 :: proc(n: ^Perlin, x, y, z: f32, octaves: int, lacunarity, gain: f32) -> f32 {
	sum: f32 = 0
	amp: f32 = 0.5
	freq: f32 = 1
	for _ in 0..<octaves {
		sum  += perlin3(n, x*freq, y*freq, z*freq) * amp
		freq *= lacunarity
		amp  *= gain
	}
	return sum
}