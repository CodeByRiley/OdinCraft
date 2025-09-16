package game

import rl      "vendor:raylib"
import render  "../render"
import blocks  "../blocks"

// If your blocks.get_defaults uses an allocator, we’ll pass context.allocator.
// Otherwise, swap to your global getter as needed.
run :: proc() {
    render.init(1280, 720, "CubeGame (Raylib)")
    defer render.shutdown()
    render.set_target_fps(0)

    // Load the 256x256 beta 1.7.3 terrain atlas (put terrain.png next to your exe or use a path)
    _ = render.load_atlas("assets/atlas.png") // returns bool; ignore for now, falls back to color if missing

    // Example camera (you can expose setters in render if you want to change it)
    cam: rl.Camera3D
    cam.position = rl.Vector3{ 16, 20, 36 }
    cam.target   = rl.Vector3{ 8,  10, 8  }
    cam.up       = rl.Vector3{ 0,  1,  0  }
    cam.fovy     = 70
    cam.projection = rl.CameraProjection.PERSPECTIVE
    render.set_camera(cam)
    render.cam_init_from_current()
    render.cam_lock_cursor()

    // Grab a couple of blocks (adjust to your allocator/global pattern)
    defaults := blocks.get_defaults(context.allocator)
    stone := defaults[0]
    dirt  := defaults[1]

    for !render.should_close() {
        render.cam_update_free(rl.GetFrameTime())
        render.begin_frame()
        render.clear_color(18, 18, 22, 255)

        // 3D pass
        render.begin_world()

        // draw a 10x1x10 stone pad at y=8
        for z in 0..<10 do for x in 0..<10 {
            render.draw_block(cast(i32)x, 8, cast(i32)z, stone)
        }

        // dirt column (y=9..13)
        for y in 9..<14 {
            render.draw_block(5, cast(i32)y, 5, dirt)
        }

        render.end_world()

        // 2D overlay
        rl.DrawFPS(10, 10)

        render.end_frame()
    }
}
