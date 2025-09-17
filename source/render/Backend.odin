package render

import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

import blk  "../blocks" // Block, UVRect, Face enum if you put it there (PX,NX,PY,NY,PZ,NZ)
import "../chunk"

//
// ── State & camera ────────────────────────────────────────────────────────────
state := struct {
    width:  i32,
    height: i32,
    inited: bool,

    atlas: rl.Texture2D,
    has_atlas: bool,

    cam: rl.Camera3D,
}{}

init :: proc(w: i32, h: i32, title: cstring) {
    if state.inited do return

    rl.SetConfigFlags(rl.ConfigFlags{.MSAA_4X_HINT, .WINDOW_RESIZABLE})
    rl.InitWindow(w, h, title)
    state.width  = w
    state.height = h
    state.inited = true

    rl.SetTargetFPS(1000)
}

shutdown :: proc() {
    if state.inited {
        if state.has_atlas {
            rl.UnloadTexture(state.atlas)
            state.has_atlas = false
        }
        rl.CloseWindow()
        state.inited = false
    }
}

set_target_fps :: proc(fps: i32) { rl.SetTargetFPS(fps) }
should_close   :: proc() -> bool { return rl.WindowShouldClose() }
begin_frame    :: proc() { rl.BeginDrawing() }
clear_color    :: proc(r, g, b, a: u8) { rl.ClearBackground(rl.Color{r, g, b, a}) }
end_frame      :: proc() { rl.EndDrawing() }
window_size    :: proc() -> (i32, i32) { return rl.GetScreenWidth(), rl.GetScreenHeight() }

//
// ── Camera helpers ────────────────────────────────────────────────────────────
//
set_camera :: proc(cam: rl.Camera3D) {
    state.cam = cam
}
get_camera :: proc() -> rl.Camera3D {
    return state.cam
}

get_camera_view_matrix :: proc() -> rl.Matrix {
	return rl.GetCameraMatrix(state.cam)
}

begin_world :: proc() {
    rl.BeginMode3D(state.cam)
    // use the atlas if present
    if state.has_atlas {
        rlgl.SetTexture(state.atlas.id)
    } else {
        rlgl.SetTexture(0)
    }
}
end_world :: proc() {
    rl.EndMode3D()
    // unbind texture
    rlgl.SetTexture(0)
}

load_atlas :: proc(path: cstring) -> bool {
    if state.has_atlas {
        rl.UnloadTexture(state.atlas)
        state.has_atlas = false
    }
    tex := rl.LoadTexture(path)
    if tex.id == 0 {
        return false
    }
    state.atlas = tex
    state.has_atlas = true

    rl.SetTextureFilter(state.atlas, rl.TextureFilter.POINT)
    rl.SetTextureWrap(state.atlas, rl.TextureWrap.CLAMP)

    return true
}

//
// ── Cube face geometry (unit cube at origin, +Y up) ───────────────────────────
//
// Face order: PX, NX, PY, NY, PZ, NZ (matches common voxel conventions)
// Vert winding is CCW when viewed from outside => backface culling works.
face_verts := [6][4]rl.Vector3{
    // +X
    {
        rl.Vector3{1,0,0}, rl.Vector3{1,1,0}, rl.Vector3{1,1,1}, rl.Vector3{1,0,1},
    },
    // -X
    {
        rl.Vector3{0,0,1}, rl.Vector3{0,1,1}, rl.Vector3{0,1,0}, rl.Vector3{0,0,0},
    },
    // +Y
    {
        rl.Vector3{0,1,1}, rl.Vector3{1,1,1}, rl.Vector3{1,1,0}, rl.Vector3{0,1,0},
    },
    // -Y
    {
        rl.Vector3{0,0,0}, rl.Vector3{1,0,0}, rl.Vector3{1,0,1}, rl.Vector3{0,0,1},
    },
    // +Z
    {
        rl.Vector3{0,0,1}, rl.Vector3{1,0,1}, rl.Vector3{1,1,1}, rl.Vector3{0,1,1},
    },
    // -Z
    {
        rl.Vector3{0,1,0}, rl.Vector3{1,1,0}, rl.Vector3{1,0,0}, rl.Vector3{0,0,0},
    },
}

//
// Map a UVRect (u0,v0,u1,v1) to a 4-corner quad in the same order as face_verts.
//
uv_quad_from_rect :: proc(r: blk.UVRect) -> [4]rl.Vector2 {
    return [4]rl.Vector2{
        rl.Vector2{ r.u0, r.v0 },
        rl.Vector2{ r.u1, r.v0 },
        rl.Vector2{ r.u1, r.v1 },
        rl.Vector2{ r.u0, r.v1 },
    }
}

//
// ── Draw one block at integer grid position with per-face UVs ─────────────────
//
// 'uvs' should be your per-face array: uvs[0..5] = PX,NX,PY,NY,PZ,NZ
// 'tint' lets you modulate (e.g., AO or biome), use WHITE for none.
//
draw_block_at :: proc(x, y, z: i32, uvs: [8]blk.UVRect, tint: rl.Color) {
    base := rl.Vector3{ cast(f32)x, cast(f32)y, cast(f32)z }

    rlgl.Begin(rlgl.QUADS)
    rlgl.Color4ub(tint.r, tint.g, tint.b, tint.a)

    for f in 0..<6 {
        quad_uv := uv_quad_from_rect(uvs[f])

        // Emit the 4 vertices (GL_QUADS style in rlgl)
        v0 := face_verts[f][0]; rlgl.TexCoord2f(quad_uv[0].x, quad_uv[0].y);       rlgl.Vertex3f(base.x+v0.x, base.y+v0.y, base.z+v0.z)
        v1 := face_verts[f][1]; rlgl.TexCoord2f(quad_uv[1].x, quad_uv[1].y); rlgl.Vertex3f(base.x+v1.x, base.y+v1.y, base.z+v1.z)
        v2 := face_verts[f][2]; rlgl.TexCoord2f(quad_uv[2].x, quad_uv[2].y); rlgl.Vertex3f(base.x+v2.x, base.y+v2.y, base.z+v2.z)
        v3 := face_verts[f][3]; rlgl.TexCoord2f(quad_uv[3].x, quad_uv[3].y); rlgl.Vertex3f(base.x+v3.x, base.y+v3.y, base.z+v3.z)
    }

    rlgl.End()
}

//
// ── Convenience: draw using a 'Block' directly ────────────────────────────────
//
draw_block :: proc(x, y, z: i32, b: blk.BlockData) {
    draw_block_at(x, y, z, b.uvs, rl.WHITE)
}


draw_chunk_debug_blocks :: proc(c: ^chunk.Chunk) {
    for x in 0..<chunk.CHUNK_SIZE_X {
        for z in 0..<chunk.CHUNK_SIZE_Z {
            for y in 0..<chunk.CHUNK_SIZE_Y {
                bt := c.blocks[x][z][y]
                if bt == blk.BlockType.Air do continue

                uvs := blk.gen_block_uvs(&c.world.atlas, bt)
                draw_block_at(cast(i32)x, cast(i32)y, cast(i32)z, uvs, rl.WHITE)
            }
        }
    }
}