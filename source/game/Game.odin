package game

import math "core:math"
import thread  "core:thread"
import sync  "core:sync"
import fmt  "core:fmt"
import si      "core:sys/info"
import rl      "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import strings "core:strings"
import render  "../render"
import blocks  "../blocks"
import helpers "../helpers"
import threading "../threading"
import _ "../shared"
import "../chunk"

remesh_q: threading.RemeshJobQueue
finished_queue: threading.FinishedChunkQueue
remesh_running := true

run :: proc() {
	rl.SetTraceLogLevel(rl.TraceLogLevel.ALL)
	blocks.init_registry()
	render.init(1600, 900, "CubeGame (Raylib)")
	defer render.shutdown()
	defer { remesh_running = false }

	helpers.init_gl_loader() 
	if !helpers.gl_custom_init() {
		panic("FATAL: Failed to load required OpenGL procedures!")
	}
	fmt.println("Custom OpenGL procedures loaded successfully.")
	render.set_target_fps(0)

    frustum: render.Frustum
    view_distance_in_chunks := 8
    MIN_VIEW_DISTANCE :: 2
    MAX_VIEW_DISTANCE :: 32 

    noise : helpers.Perlin
	helpers.perlin_init(&noise, 1337)
	world : chunk.World
	chunk.world_init(&world, 0.0)
	tex := rl.LoadTexture("assets/atlas.png")
	rl.SetTextureFilter(tex, rl.TextureFilter.POINT)
	chunk.world_set_atlas_texture(&world, tex)

    voxel_shader := rl.LoadShader("assets/shaders/VoxelAO.vert.glsl", "assets/shaders/VoxelAO.frag.glsl")
    opacity_tex_loc  := rl.GetShaderLocation(voxel_shader, "opacityData")
    light_tex_loc    := rl.GetShaderLocation(voxel_shader, "lightData")
    chunk_offset_loc := rl.GetShaderLocation(voxel_shader, "chunkOffset")
    debug_mode_loc   := rl.GetShaderLocation(voxel_shader, "debugMode")

	tp := chunk.default_terrain_params()
	tp.use_water   = true

	rargs := new(threading.RemeshWorkerArgs)
	rargs.job_q  = &remesh_q
	rargs.out_q  = &finished_queue
	rargs.running = &remesh_running
	rth := thread.create(threading.remesh_worker_proc)
	rth.user_args[0] = rargs
	thread.start(rth)
	append(&threading.threads, rth)

	world_seed : u32 = 1337
	num_workers := si.cpu.logical_cores - 1 
	if num_workers < 1 do num_workers = 1
	
    cam: rl.Camera3D
	cam.position   = {0, 80, 0}
	cam.target     = {1, 80,  1}
	cam.up         = {0,  1,  0}
	cam.fovy       = 70
	cam.projection = .PERSPECTIVE
	render.set_camera(cam)
	render.cam_init_from_current()
	render.cam_lock_cursor()

	last_cam_chunk_x, last_cam_chunk_z := math.max(int), math.max(int)
	
    debug_mode: i32 = 0
    debug_mode_text: string

	for !render.should_close() {
		render.cam_update_free(rl.GetFrameTime())

        if rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD) { view_distance_in_chunks = min(view_distance_in_chunks + 1, MAX_VIEW_DISTANCE) }
        if rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT) { view_distance_in_chunks = max(view_distance_in_chunks - 1, MIN_VIEW_DISTANCE) }
		if rl.IsKeyPressed(.V) { render.set_flag_runtime(rl.ConfigFlag.VSYNC_HINT, !render.is_flag_active(.VSYNC_HINT)) }
        if rl.IsKeyPressed(.ZERO) { debug_mode = 0 }
        if rl.IsKeyPressed(.ONE) { debug_mode = 1 }
        if rl.IsKeyPressed(.TWO) { debug_mode = 2 }
        if rl.IsKeyPressed(.THREE) { debug_mode = 3 }
        if rl.IsKeyPressed(.FOUR) { debug_mode = 4 }

        current_cam := render.get_camera()
		cam_chunk_x := cast(int) math.floor(current_cam.position.x / f32(chunk.CHUNK_SIZE_X))
		cam_chunk_z := cast(int) math.floor(current_cam.position.z / f32(chunk.CHUNK_SIZE_Z))

		if cam_chunk_x != last_cam_chunk_x || cam_chunk_z != last_cam_chunk_z {
			last_cam_chunk_x = cam_chunk_x
			last_cam_chunk_z = cam_chunk_z

			gen_radius := max(view_distance_in_chunks - 1, MIN_VIEW_DISTANCE)
			unload_radius := view_distance_in_chunks
			gen_radius_sq    := gen_radius * gen_radius
			unload_radius_sq := unload_radius * unload_radius

			chunks_to_remove: [dynamic][2]int
			for pos, c in world.chunks {
				dx := c.cx - cam_chunk_x
				dz := c.cz - cam_chunk_z
				if dx*dx + dz*dz > unload_radius_sq {
                    sync.atomic_store(&c.alive, false)
					append(&chunks_to_remove, pos)
				}
			}

			for pos in chunks_to_remove { delete_key(&world.chunks, pos) }
			delete(chunks_to_remove)

			chunks_to_generate: [dynamic]^chunk.Chunk
			for z in -gen_radius..=gen_radius {
				for x in -gen_radius..=gen_radius {
					if x*x + z*z > gen_radius_sq { continue }
					cx := cam_chunk_x + x
					cz := cam_chunk_z + z
					if _, ok := world.chunks[[2]int{cx, cz}]; !ok {
						c := new(chunk.Chunk)
						chunk.chunk_init(c, cx, cz)
						chunk.world_add_chunk(&world, c)
						append(&chunks_to_generate, c)
					}
				}
			}

			if len(chunks_to_generate) > 0 {
				workers_to_spawn := min(num_workers, len(chunks_to_generate))
				fmt.printf("Spawning %v worker threads for %v new chunks...\n", workers_to_spawn, len(chunks_to_generate))
				for w in 0..<workers_to_spawn {
					wa := new(threading.WorkerArgs)
					wa.chunks_to_generate = chunks_to_generate
					wa.start, wa.stride = w, workers_to_spawn
					wa.noise, wa.seed, wa.params = &noise, world_seed, tp
					wa.finished_queue = &finished_queue
					t := thread.create(threading.worker_proc)
					t.user_args[0] = wa
					thread.start(t)
					append(&threading.threads, t)
				}
			}
		}

        // CORRECTED: Final, safe finished work loop.
        MAX_MESHES_PER_FRAME :: 8
        for _ in 0..<MAX_MESHES_PER_FRAME {
            if work, ok := threading.queue_pop(&finished_queue); ok {
                finished_chunk := (^chunk.Chunk)(work.chunk_ptr)
                if finished_chunk != nil && sync.atomic_load(&finished_chunk.alive) {
                    chunk.chunk_upload_geometry(finished_chunk, work.geometry)
                    chunk.chunk_upload_gpu_data(finished_chunk, work.opacity_data, work.light_data)
                    dirs := [][2]int{{+1,0},{-1,0},{0,+1},{0,-1},{+1,+1},{+1,-1},{-1,+1},{-1,-1}}
                    for d in dirs {
                        nb := chunk.world_get_chunk(&world, finished_chunk.cx + d[0], finished_chunk.cz + d[1])
                        if nb != nil && sync.atomic_load(&nb.alive) {
                            threading.remesh_push_unique(&remesh_q, nb)
                        }
                    }
                } else if finished_chunk != nil {
                    chunk.chunk_unload_gpu(finished_chunk)
                    chunk.chunk_unload_gpu_data(finished_chunk)
                    chunk.free_geometry(work.geometry)
                    delete(work.opacity_data)
                    delete(work.light_data)
                    free(finished_chunk)
                }
            } else { break }
        }
        
        view_matrix := render.get_camera_view_matrix()
		proj_matrix := rl.GetCameraProjectionMatrix(&current_cam, 16.0/9.0)
		view_proj_matrix := proj_matrix * view_matrix
		render.frustum_update(&frustum, view_proj_matrix)

        visible_chunks := 0
        render.begin_frame()
        render.clear_color(18, 18, 22, 255)
        
        render.begin_world()
            rl.BeginShaderMode(voxel_shader)
                rl.SetShaderValue(voxel_shader, debug_mode_loc, &debug_mode, .INT)
                for _, c in world.chunks {
                    aabb := chunk.get_chunk_aabb(c)
                    dist_sq := rl.Vector3DistanceSqrt(current_cam.position, aabb.min + (aabb.max - aabb.min)*0.5)
                    if dist_sq <= f32(view_distance_in_chunks*view_distance_in_chunks*chunk.CHUNK_SIZE_X*chunk.CHUNK_SIZE_X) && render.frustum_check_aabb(&frustum, aabb) {
                        if c.model.meshCount > 0 {
                            c.model.materials[0].shader = voxel_shader
                            chunk_origin := rl.Vector3{f32(c.cx * chunk.CHUNK_SIZE_X), 0, f32(c.cz * chunk.CHUNK_SIZE_Z)}
                            rl.SetShaderValue(voxel_shader, chunk_offset_loc, &chunk_origin, .VEC3)
                            i32_2, i32_3 : i32 = 2, 3
                            rlgl.ActiveTextureSlot(2)
                            rlgl.SetTexture(c.opacity_tex_id)
                            rl.SetShaderValue(voxel_shader, opacity_tex_loc, &i32_2, .INT)
                            rlgl.ActiveTextureSlot(3)
                            rlgl.SetTexture(c.light_tex_id)
                            rl.SetShaderValue(voxel_shader, light_tex_loc, &i32_3, .INT)
                            rlgl.ActiveTextureSlot(0)
                            chunk.chunk_draw_opaque(c)
                            visible_chunks += 1
                        }
                    }
                }
            rl.EndShaderMode()

			for _, c in world.chunks {
                aabb := chunk.get_chunk_aabb(c)
                dist_sq := rl.Vector3DistanceSqrt(current_cam.position, aabb.min + (aabb.max - aabb.min)*0.5)
                if dist_sq <= f32(view_distance_in_chunks*view_distance_in_chunks*chunk.CHUNK_SIZE_X*chunk.CHUNK_SIZE_X) && render.frustum_check_aabb(&frustum, aabb) {
					chunk.chunk_draw_water(c)
                }
			}
		render.end_world()

        switch debug_mode {
        case 0: debug_mode_text = "Mode: 0 (Final Composite)"
        case 1: debug_mode_text = "Mode: 1 (Atlas Texture)"
        case 2: debug_mode_text = "Mode: 2 (Vertex Tint)"
        case 3: debug_mode_text = "Mode: 3 (Light Map)"
        case 4: debug_mode_text = "Mode: 4 (Ambient Occlusion)"
        }
		
        debug_text_str := fmt.tprintf("Visible Chunks: %d / %d", visible_chunks, len(world.chunks))
        render_str := fmt.tprintf("Render Distance: %d / %d",view_distance_in_chunks, MAX_VIEW_DISTANCE)
		vsync_str := fmt.tprintf("VSync: %v\n", render.is_flag_active(.VSYNC_HINT))
        rl.DrawText(strings.clone_to_cstring(debug_mode_text, context.temp_allocator), 10, 115, 20, rl.YELLOW)
        rl.DrawText(strings.clone_to_cstring(debug_text_str, context.temp_allocator), 10, 40, 20, rl.LIME)
        rl.DrawText(strings.clone_to_cstring(render_str, context.temp_allocator), 10, 65, 20, rl.LIME)
        rl.DrawText(strings.clone_to_cstring(vsync_str, context.temp_allocator), 10, 90, 20, rl.LIME)
		rl.DrawFPS(10, 10)
        render.end_frame()
    }
}