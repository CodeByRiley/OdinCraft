package game

import math "core:math"
import thread  "core:thread"
import sync  "core:sync"
import fmt  "core:fmt"
import si      "core:sys/info"
import rl      "vendor:raylib"
import strings "core:strings"
import render  "../render"
import blocks  "../blocks"
import "../helpers"
import "../chunk"
import "../shared"

// Array of threads
threads: [dynamic]^thread.Thread

// NEW: A list to hold chunks that are marked for deletion.
// We will free them on the next frame to ensure no worker thread is still using them.
purgatory: [dynamic]^chunk.Chunk 

FinishedChunkQueue :: struct {
    work:  [dynamic]shared.FinishedWork,
    mutex: sync.Mutex,
}

// queue_push is called by worker threads
queue_push :: proc(q: ^FinishedChunkQueue, work: shared.FinishedWork) {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)
    append(&q.work, work)
}

// queue_pop is called by the main thread
queue_pop :: proc(q: ^FinishedChunkQueue) -> (work: shared.FinishedWork, ok: bool) {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)

    if len(q.work) > 0 {
        work = q.work[0]
        ok = true
        ordered_remove(&q.work, 0)
        return
    }
    return shared.FinishedWork{}, false
}

WorkerArgs :: struct {
    chunks_to_generate: [dynamic]^chunk.Chunk,
    start:   int,
    stride:  int,
    noise:          ^helpers.Perlin,
    seed:           u32,
    params:         chunk.TerrainParams,
    finished_queue: ^FinishedChunkQueue,
}

// --- CORRECTED AND THREAD-SAFE WORKER PROCEDURE ---
worker_proc :: proc(t: ^thread.Thread) {
    args := (^WorkerArgs)(t.user_args[0])
    for i := args.start; i < len(args.chunks_to_generate); i += args.stride {
        c := args.chunks_to_generate[i]
        
        // CRITICAL CHECK 1: Before doing ANY work, check if the chunk is still alive.
        if !sync.atomic_load(&c.alive) {
            continue // Skip this chunk; it was unloaded before we could start.
        }

        // Generate block data. This function now has internal checks as well.
        chunk.chunk_generate_perlin(c, args.noise, args.seed, args.params)

        // CRITICAL CHECK 2: Check again after generation and before the expensive meshing process.
        if !sync.atomic_load(&c.alive) {
            continue
        }

        // Build mesh geometry
        geometry := chunk.chunk_build_geometry(c)

        // CRITICAL CHECK 3: Final check before pushing the result to the main thread.
        if sync.atomic_load(&c.alive) {
            work := shared.FinishedWork{
                chunk_ptr = rawptr(c),
                geometry  = geometry,
            }
            queue_push(args.finished_queue, work)
        }
    }
}

run :: proc() {
	rl.SetTraceLogLevel(rl.TraceLogLevel.ALL)
	blocks.init_registry()
	render.init(1600, 900, "CubeGame (Raylib)")
	defer render.shutdown()
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

	tp := chunk.default_terrain_params()
	tp.use_water   = true

	finished_queue: FinishedChunkQueue
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
	
	for !render.should_close() {
		render.cam_update_free(rl.GetFrameTime())

        if rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD) {
            view_distance_in_chunks = min(view_distance_in_chunks + 1, MAX_VIEW_DISTANCE)
        }
        if rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT) {
            view_distance_in_chunks = max(view_distance_in_chunks - 1, MIN_VIEW_DISTANCE)
        }

        current_cam := render.get_camera()
		cam_chunk_x := cast(int) math.floor(current_cam.position.x / f32(chunk.CHUNK_SIZE_X))
		cam_chunk_z := cast(int) math.floor(current_cam.position.z / f32(chunk.CHUNK_SIZE_Z))

		if cam_chunk_x != last_cam_chunk_x || cam_chunk_z != last_cam_chunk_z {
			last_cam_chunk_x = cam_chunk_x
			last_cam_chunk_z = cam_chunk_z

            // --- CORRECTED UNLOAD/LOAD LOGIC WITH PURGATORY ---

            // STEP 1: Process the Purgatory (SAFE SHUTDOWN)
            // Free the chunks that were marked for death on the PREVIOUS frame.
            for c in purgatory {
                chunk.chunk_unload_gpu(c)
                free(c)
            }
            clear(&purgatory)

			gen_radius := max(view_distance_in_chunks - 1, MIN_VIEW_DISTANCE)
			unload_radius := view_distance_in_chunks
			gen_radius_sq    := gen_radius * gen_radius
			unload_radius_sq := unload_radius * unload_radius

			// STEP 2: Mark distant chunks for death and move them to the purgatory
			chunks_to_remove: [dynamic][2]int
			for pos, c in world.chunks {
				dx := c.cx - cam_chunk_x
				dz := c.cz - cam_chunk_z
				if dx*dx + dz*dz > unload_radius_sq {
                    // Signal to workers that this chunk is dead.
                    sync.atomic_store(&c.alive, false)
					append(&chunks_to_remove, pos)
                    // Add it to purgatory to be freed next frame.
					append(&purgatory, c)
				}
			}

            // Remove dead chunks from the active world map.
			for pos in chunks_to_remove {
				delete_key(&world.chunks, pos)
			}
			delete(chunks_to_remove)

			// Load new chunks
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
					wa := new(WorkerArgs)
					wa.chunks_to_generate = chunks_to_generate
					wa.start   = w
					wa.stride  = workers_to_spawn
					wa.noise   = &noise
					wa.seed    = world_seed
					wa.params  = tp
					wa.finished_queue = &finished_queue

					t := thread.create(worker_proc)
					t.user_args[0] = wa
					thread.start(t)
					append(&threads, t)
				}
			}
		}

        max_draw_distance := f32(view_distance_in_chunks) * f32(chunk.CHUNK_SIZE_X)
        max_dist_sq := max_draw_distance * max_draw_distance
		MAX_MESHES_PER_FRAME :: 8
		for _ in 0..<MAX_MESHES_PER_FRAME {
			if work, ok := queue_pop(&finished_queue); ok {
				finished_chunk := (^chunk.Chunk)(work.chunk_ptr)
                // Add a final safety check: only upload if the chunk is still alive.
                if finished_chunk != nil && sync.atomic_load(&finished_chunk.alive) {
				    chunk.chunk_upload_geometry(finished_chunk, work.geometry)
                }
			} else {
				break
			}
		}
        
        view_matrix := render.get_camera_view_matrix()
		proj_matrix := rl.GetCameraProjectionMatrix(&current_cam, 16.0/9.0)
		view_proj_matrix := proj_matrix * view_matrix
		render.frustum_update(&frustum, view_proj_matrix)

        visible_chunks := 0
        render.begin_frame()
        render.clear_color(18, 18, 22, 255)
        render.begin_world()
			for _, c in world.chunks {
				aabb := chunk.get_chunk_aabb(c)
                chunk_center := aabb.min + ((aabb.max - aabb.min) * 0.5)
                dist_sq := rl.Vector3DistanceSqrt(current_cam.position, chunk_center)
                if dist_sq <= max_dist_sq && render.frustum_check_aabb(&frustum, aabb) {
                    chunk.chunk_draw_opaque(c)
                    visible_chunks += 1
                }
			}
			for _, c in world.chunks {
				aabb := chunk.get_chunk_aabb(c)
                chunk_center := aabb.min + ((aabb.max - aabb.min) * 0.5)
                dist_sq := rl.Vector3DistanceSqrt(current_cam.position, chunk_center)
                if dist_sq <= max_dist_sq && render.frustum_check_aabb(&frustum, aabb) {
                    chunk.chunk_draw_water(c)
                }
			}
		render.end_world()

		rl.DrawFPS(10, 10)
        total_chunks := len(world.chunks)
        debug_text_str := fmt.tprintf("Visible Chunks: %d / %d", visible_chunks, total_chunks)
        render_str := fmt.tprintf("Render Distance: %d / %d",view_distance_in_chunks, MAX_VIEW_DISTANCE)
        debug_text_cstr := strings.clone_to_cstring(debug_text_str, context.temp_allocator)
        render_cstr := strings.clone_to_cstring(render_str, context.temp_allocator)

        rl.DrawText(debug_text_cstr, 10, 40, 20, rl.LIME)
        rl.DrawText(render_cstr, 10, 65, 20, rl.LIME)
        render.end_frame()
    }
}