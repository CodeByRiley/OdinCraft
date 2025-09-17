package render

import rl   "vendor:raylib"
import math "core:math"

// ───────────────── Camera Controller (free-fly) ─────────────────

// `controller` is a package-level variable that holds the state for the free-fly camera,
// such as its orientation (yaw/pitch) and movement settings.
controller := struct {
	yaw, pitch:   f32, // The orientation of the camera in degrees.
	speed:        f32, // Base movement speed in units per second.
	mouse_sens:   f32, // Mouse sensitivity for looking around.
	fast_mult:    f32, // Speed multiplier when holding 'fast' key (e.g., Shift).
	slow_mult:    f32, // Speed multiplier when holding 'slow' key (e.g., Alt).
	cursor_locked: bool, // Whether the mouse cursor is hidden and locked for looking.
}{}

// NOTE: Since your project now uses modern rl-odin, these helpers are not strictly necessary
// as you can use operators directly (e.g., a + b, a - b, a * s). They are kept here
// as they are part of the original file.
v3_add   :: proc(a, b: rl.Vector3) -> rl.Vector3 { return a + b }
v3_sub   :: proc(a, b: rl.Vector3) -> rl.Vector3 { return a - b }
v3_scale :: proc(a: rl.Vector3, s: f32) -> rl.Vector3 { return a * s }
v3_len   :: proc(a: rl.Vector3) -> f32 { return math.sqrt(a.x*a.x + a.y*a.y + a.z*a.z) }


// cam_init_defaults resets the camera controller to its default settings.
cam_init_defaults :: proc() {
	controller.yaw         = 0
	controller.pitch       = 0
	controller.speed       = 8.0
	controller.mouse_sens  = 0.2
	controller.fast_mult   = 4.0
	controller.slow_mult   = 0.25
	controller.cursor_locked = false
}

// cam_init_from_current synchronizes the controller's yaw and pitch angles based on
// the camera's existing position and target vectors. This should be called once after
// the main camera is first set up to ensure the controller starts with the correct orientation.
cam_init_from_current :: proc() {
	cam_init_defaults()

	// Calculate the direction vector the camera is currently pointing in.
	dir := state.cam.target - state.cam.position

	// Calculate yaw (rotation around the Y-axis) from the X and Z components of the direction.
	controller.yaw   = math.atan2(dir.z, dir.x) * rl.RAD2DEG
	// Calculate pitch (up/down rotation) from the Y component and the length of the XZ plane projection.
	len_xz := math.sqrt(dir.x*dir.x + dir.z*dir.z)
	controller.pitch = math.atan2(dir.y, len_xz) * rl.RAD2DEG

	// Clamp the initial pitch to prevent the camera from flipping over.
	if controller.pitch < -89 { controller.pitch = -89 }
	if controller.pitch >  +89 { controller.pitch = +89 }
}

// cam_lock_cursor hides and locks the cursor to the center of the screen for mouse look.
cam_lock_cursor   :: proc() { rl.DisableCursor(); controller.cursor_locked = true  }
// cam_unlock_cursor shows and frees the cursor.
cam_unlock_cursor :: proc() { rl.EnableCursor();  controller.cursor_locked = false }
// cam_toggle_cursor switches between the locked and unlocked cursor states.
cam_toggle_cursor :: proc() {
	if controller.cursor_locked { cam_unlock_cursor() } else { cam_lock_cursor() }
}
// cam_cursor_locked returns true if the cursor is currently locked.
cam_cursor_locked :: proc() -> bool { return controller.cursor_locked }

// cam_set_speed sets the base movement speed of the camera.
cam_set_speed        :: proc(base_speed: f32) { controller.speed = base_speed }
// cam_set_speed_scales sets the multipliers for fast and slow movement modes.
cam_set_speed_scales :: proc(fast_mult, slow_mult: f32) {
	controller.fast_mult = fast_mult
	controller.slow_mult = slow_mult
}
// cam_set_sensitivity sets the mouse look sensitivity.
cam_set_sensitivity  :: proc(sens: f32) { controller.mouse_sens = sens }

// cam_update_free should be called every frame to update the free-fly camera's
// state based on user input. `dt` is delta time (rl.GetFrameTime()).
cam_update_free :: proc(dt: f32) {
	// Toggle cursor lock with the Right Mouse Button.
	if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
		cam_toggle_cursor()
	}

	// Update camera orientation based on mouse movement if the cursor is locked.
	if controller.cursor_locked {
		dm := rl.GetMouseDelta()
		controller.yaw   += (dm.x * controller.mouse_sens)
		controller.pitch -= (dm.y * controller.mouse_sens)
		// Clamp pitch to prevent looking straight up or down, which can cause gimbal lock.
		if controller.pitch < -89 { controller.pitch = -89 }
		if controller.pitch >  +89 { controller.pitch = +89 }
	}

	// Calculate the camera's forward, right, and up vectors from the yaw and pitch angles.
	yaw_r   := controller.yaw   * rl.DEG2RAD
	pitch_r := controller.pitch * rl.DEG2RAD

	fwd := rl.Vector3{
		math.cos(yaw_r) * math.cos(pitch_r),
		math.sin(pitch_r),
		math.sin(yaw_r) * math.cos(pitch_r),
	}
	right := rl.Vector3{ -fwd.z, 0, fwd.x } // Right vector is perpendicular to forward on the XZ plane.
	up    := rl.Vector3{ 0, 1, 0 }

	// Determine the current speed based on modifier keys.
	spd := controller.speed
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) do spd *= controller.fast_mult
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_ALT)   do spd *= controller.slow_mult

	// Aggregate keyboard inputs to create a velocity direction vector.
	vel := rl.Vector3{}
	if rl.IsKeyDown(rl.KeyboardKey.W)            do vel = vel + fwd
	if rl.IsKeyDown(rl.KeyboardKey.S)            do vel = vel - fwd
	if rl.IsKeyDown(rl.KeyboardKey.D)            do vel = vel + right
	if rl.IsKeyDown(rl.KeyboardKey.A)            do vel = vel - right
	if rl.IsKeyDown(rl.KeyboardKey.SPACE)        do vel = vel + up
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_CONTROL) do vel = vel - up

	// Update the camera's position.
	l := v3_len(vel)
	if l > 0.0001 { // Only move if there is input.
		// Normalize the velocity vector and scale it by speed and delta time.
		// This ensures consistent movement speed regardless of direction or frame rate.
		vel = v3_scale(vel, (spd * dt) / l)
		state.cam.position = state.cam.position + vel
	}

	// Always update the camera's target to be one unit in front of its new position.
	// This ensures mouse look works even when the camera is stationary.
	state.cam.target = state.cam.position + fwd
}