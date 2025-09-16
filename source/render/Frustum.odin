package render

import rl "vendor:raylib"

FRUSTUM_PLANE :: enum {
	RIGHT = 0,
	LEFT,
	BOTTOM,
	TOP,
	FAR,  // Corresponds to the "back" plane
	NEAR, // Corresponds to the "front" plane
}

// A plane is defined by the equation Ax + By + Cz + D = 0.
// `normal` is the (A, B, C) part.
// `distance` is the D part.
Plane :: struct {
	normal:   rl.Vector3,
	distance: f32,
}

// A Frustum is simply a collection of 6 planes.
Frustum :: struct {
	planes: [6]Plane,
}

// A private helper procedure to normalize a plane.
// The leading underscore `_` is an Odin convention for private procedures.
_normalize_plane :: proc(p: Plane) -> Plane {
	result := p
	mag := rl.Vector3Length(p.normal)

	// Avoid division by zero
	if mag != 0 {
		result.normal.x /= mag
		result.normal.y /= mag
		result.normal.z /= mag
		result.distance /= mag
	}
	return result
}


// Updates the frustum's planes based on a combined view-projection matrix.
// This should be called every frame the camera moves.
frustum_update :: proc(f: ^Frustum, view_proj: rl.Matrix) {
	// Left Plane
	f.planes[FRUSTUM_PLANE.LEFT].normal.x = view_proj[3][0] + view_proj[0][0]
	f.planes[FRUSTUM_PLANE.LEFT].normal.y = view_proj[3][1] + view_proj[0][1]
	f.planes[FRUSTUM_PLANE.LEFT].normal.z = view_proj[3][2] + view_proj[0][2]
	f.planes[FRUSTUM_PLANE.LEFT].distance   = view_proj[3][3] + view_proj[0][3]
	
	// Right Plane
	f.planes[FRUSTUM_PLANE.RIGHT].normal.x = view_proj[3][0] - view_proj[0][0]
	f.planes[FRUSTUM_PLANE.RIGHT].normal.y = view_proj[3][1] - view_proj[0][1]
	f.planes[FRUSTUM_PLANE.RIGHT].normal.z = view_proj[3][2] - view_proj[0][2]
	f.planes[FRUSTUM_PLANE.RIGHT].distance   = view_proj[3][3] - view_proj[0][3]

	// Bottom Plane
	f.planes[FRUSTUM_PLANE.BOTTOM].normal.x = view_proj[3][0] + view_proj[1][0]
	f.planes[FRUSTUM_PLANE.BOTTOM].normal.y = view_proj[3][1] + view_proj[1][1]
	f.planes[FRUSTUM_PLANE.BOTTOM].normal.z = view_proj[3][2] + view_proj[1][2]
	f.planes[FRUSTUM_PLANE.BOTTOM].distance   = view_proj[3][3] + view_proj[1][3]

	// Top Plane
	f.planes[FRUSTUM_PLANE.TOP].normal.x = view_proj[3][0] - view_proj[1][0]
	f.planes[FRUSTUM_PLANE.TOP].normal.y = view_proj[3][1] - view_proj[1][1]
	f.planes[FRUSTUM_PLANE.TOP].normal.z = view_proj[3][2] - view_proj[1][2]
	f.planes[FRUSTUM_PLANE.TOP].distance   = view_proj[3][3] - view_proj[1][3]

	// Near Plane
	f.planes[FRUSTUM_PLANE.NEAR].normal.x = view_proj[3][0] + view_proj[2][0]
	f.planes[FRUSTUM_PLANE.NEAR].normal.y = view_proj[3][1] + view_proj[2][1]
	f.planes[FRUSTUM_PLANE.NEAR].normal.z = view_proj[3][2] + view_proj[2][2]
	f.planes[FRUSTUM_PLANE.NEAR].distance   = view_proj[3][3] + view_proj[2][3]

	// Far Plane
	f.planes[FRUSTUM_PLANE.FAR].normal.x = view_proj[3][0] - view_proj[2][0]
	f.planes[FRUSTUM_PLANE.FAR].normal.y = view_proj[3][1] - view_proj[2][1]
	f.planes[FRUSTUM_PLANE.FAR].normal.z = view_proj[3][2] - view_proj[2][2]
	f.planes[FRUSTUM_PLANE.FAR].distance   = view_proj[3][3] - view_proj[2][3]

	// Normalize all the planes
	for i in 0..<6 {
		f.planes[i] = _normalize_plane(f.planes[i])
	}
}

// Checks if an Axis-Aligned Bounding Box (AABB) is inside the frustum.
// If the box is outside any single plane, it's culled.
frustum_check_aabb :: proc(f: ^Frustum, aabb: rl.BoundingBox) -> bool {
	for plane in f.planes {
		// Find the vertex of the AABB that is "most positive"
		// with respect to the plane's normal vector.
		p_vertex: rl.Vector3

        if (plane.normal.x > 0) {
            p_vertex.x = aabb.max.x
        } else {
            p_vertex.x = aabb.min.x
        }
        if (plane.normal.y > 0) {
            p_vertex.y = aabb.max.y
        } else {
            p_vertex.y = aabb.min.y
        }
        if (plane.normal.z > 0) {
            p_vertex.z = aabb.max.z
        } else {
            p_vertex.z = aabb.min.z
        }

		// Calculate the signed distance from this vertex to the plane.
		// If it's negative, the entire box is on the outside of the plane.
		if rl.Vector3DotProduct(plane.normal, p_vertex) + plane.distance < 0 {
			return false // Culled: The box is outside this plane
		}
	}

	return true // Visible: The box intersects all planes
}