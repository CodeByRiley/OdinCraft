package render

import rl   "vendor:raylib"
import math "core:math"

// ───────────────── Camera Controller (free-fly) ─────────────────

controller := struct {
    yaw, pitch: f32,
    speed:      f32,
    mouse_sens: f32,
    fast_mult:  f32,
    slow_mult:  f32,
    cursor_locked: bool,
}{}

// Simple Vector3 helpers (raylib-odin doesn’t include the C helpers)
v3_add   :: proc(a, b: rl.Vector3) -> rl.Vector3 { return rl.Vector3{ a.x+b.x, a.y+b.y, a.z+b.z } }
v3_sub   :: proc(a, b: rl.Vector3) -> rl.Vector3 { return rl.Vector3{ a.x-b.x, a.y-b.y, a.z-b.z } }
v3_scale :: proc(a: rl.Vector3, s: f32) -> rl.Vector3 { return rl.Vector3{ a.x*s, a.y*s, a.z*s } }
v3_len   :: proc(a: rl.Vector3) -> f32 { return math.sqrt(a.x*a.x + a.y*a.y + a.z*a.z) }

cam_init_defaults :: proc() {
    controller.yaw         = 0
    controller.pitch       = 0
    controller.speed       = 8.0
    controller.mouse_sens  = 0.2
    controller.fast_mult   = 4.0
    controller.slow_mult   = 0.25
    controller.cursor_locked = false
}

// Call once after state.cam is set (e.g., from render.init or your game)
cam_init_from_current :: proc() {
    cam_init_defaults()

    dir := v3_sub(state.cam.target, state.cam.position)

    // yaw around +Y axis (atan2(z, x)), then pitch relative to XZ length
    controller.yaw   = math.atan2(dir.z, dir.x) * rl.RAD2DEG
    len_xz := math.sqrt(dir.x*dir.x + dir.z*dir.z)
    controller.pitch = math.atan2(dir.y, len_xz) * rl.RAD2DEG

    // clamp pitch to avoid gimbal flip
    if controller.pitch < -89 { controller.pitch = -89 }
    if controller.pitch >  +89 { controller.pitch = +89 }
}

cam_lock_cursor   :: proc() { rl.DisableCursor(); controller.cursor_locked = true  }
cam_unlock_cursor :: proc() { rl.EnableCursor();  controller.cursor_locked = false }
cam_toggle_cursor :: proc() {
    if controller.cursor_locked { cam_unlock_cursor() } else { cam_lock_cursor() }
}
cam_cursor_locked :: proc() -> bool { return controller.cursor_locked }

cam_set_speed        :: proc(base_speed: f32) { controller.speed = base_speed }
cam_set_speed_scales :: proc(fast_mult, slow_mult: f32) {
    controller.fast_mult = fast_mult
    controller.slow_mult = slow_mult
}
cam_set_sensitivity  :: proc(sens: f32) { controller.mouse_sens = sens }

// Call every frame with dt = rl.GetFrameTime()
cam_update_free :: proc(dt: f32) {
    // Toggle lock with RMB
    if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
        cam_toggle_cursor()
    }

    // Mouse look
    if controller.cursor_locked {
        dm := rl.GetMouseDelta()
        controller.yaw   += (dm.x * controller.mouse_sens)
        controller.pitch -= (dm.y * controller.mouse_sens)
        if controller.pitch < -89 { controller.pitch = -89 }
        if controller.pitch >  +89 { controller.pitch = +89 }
    }

    // Build forward/right/up from yaw/pitch
    yaw_r   := controller.yaw   * rl.DEG2RAD
    pitch_r := controller.pitch * rl.DEG2RAD

    fwd := rl.Vector3{
        math.cos(yaw_r) * math.cos(pitch_r),
        math.sin(pitch_r),
        math.sin(yaw_r) * math.cos(pitch_r),
    }
    right := rl.Vector3{ -fwd.z, 0, fwd.x }
    up    := rl.Vector3{ 0, 1, 0 }

    // Movement input
    spd := controller.speed
    if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) do spd *= controller.fast_mult
    if rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT)   do spd *= controller.slow_mult

    vel := rl.Vector3{}
    if rl.IsKeyDown(rl.KeyboardKey.W)            do vel = v3_add(vel, fwd)
    if rl.IsKeyDown(rl.KeyboardKey.S)            do vel = v3_sub(vel, fwd)
    if rl.IsKeyDown(rl.KeyboardKey.D)            do vel = v3_add(vel, right)
    if rl.IsKeyDown(rl.KeyboardKey.A)            do vel = v3_sub(vel, right)
    if rl.IsKeyDown(rl.KeyboardKey.SPACE)        do vel = v3_add(vel, up)
    if rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) do vel = v3_sub(vel, up)

    l := v3_len(vel)
    if l > 0.0001 {
        vel = v3_scale(vel, (spd * dt) / l)
        state.cam.position = v3_add(state.cam.position, vel)
    }
    // Always update target from latest yaw/pitch so look works when stationary
    state.cam.target = v3_add(state.cam.position, fwd)
}