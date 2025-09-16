package game

import thread  "core:thread"
import sync  "core:sync"
import fmt  "core:fmt"
import si      "core:sys/info"
import rl      "vendor:raylib"
import strings "core:strings"
import render  "../render"
import blocks  "../blocks"
//import mem "core:mem"
import "../helpers"
import "../chunk"

// 8 x 8 of 32 x 32 chunks
WORLD_SIZE_X :: 8 // 8 chunks x
WORLD_SIZE_Z :: 8 // 8 chunkz z

// Array of threads
threads: [dynamic]^thread.Thread

FinishedChunkQueue :: struct {
	chunks: [dynamic]^chunk.Chunk,
	mutex:  sync.Mutex,
}

// queue_push is called by worker threads
queue_push :: proc(q: ^FinishedChunkQueue, c: ^chunk.Chunk) {
	sync.mutex_lock(&q.mutex)
	defer sync.mutex_unlock(&q.mutex)
	append(&q.chunks, c)
}

// queue_pop is called by the main thread
queue_pop :: proc(q: ^FinishedChunkQueue) -> (c: ^chunk.Chunk, ok: bool) {
	sync.mutex_lock(&q.mutex)
	defer sync.mutex_unlock(&q.mutex)

	if len(q.chunks) > 0 {
		c = q.chunks[0]
		ok = true
		ordered_remove(&q.chunks, 0)
		return
	}
	return nil, false
}

WorkerArgs :: struct {
	chunks:         []^chunk.Chunk,
	noise:          ^helpers.Perlin,
	seed:           u32,
	params:         chunk.TerrainParams,
	finished_queue: ^FinishedChunkQueue,

	next_idx:       i32,
	next_mutex:     sync.Mutex,
}

worker_proc :: proc(t: ^thread.Thread) {
	// Retrieve the pointer from the user_args array.
	args := (^WorkerArgs)(t.user_args[0])
	
	num_chunks := len(args.chunks)

	for {
		idx: i32
		sync.mutex_lock(&args.next_mutex)
		idx = args.next_idx
		args.next_idx += 1
		sync.mutex_unlock(&args.next_mutex)

		if idx >= i32(num_chunks) {
			break
		}

		c := args.chunks[idx]
		chunk.chunk_generate_perlin(c, args.noise, args.seed, args.params)
		queue_push(args.finished_queue, c)
	}
}

run :: proc() {
	render.init(1280, 720, "CubeGame (Raylib)")
	defer render.shutdown()
	render.set_target_fps(0)

    frustum: render.Frustum

    view_distance_in_chunks := 8
    // Define min/max so it doesn't go crazy.
    MIN_VIEW_DISTANCE :: 2
    MAX_VIEW_DISTANCE :: 128

    // Noise
	noise : helpers.Perlin
	helpers.perlin_init(&noise, 1337)

	// World + atlas
	world : chunk.World
	chunk.world_init(&world, 0.0)
	tex := rl.LoadTexture("assets/atlas.png")
	rl.SetTextureFilter(tex, rl.TextureFilter.POINT)
	chunk.world_set_atlas_texture(&world, tex)

	// Terrain params
	tp := chunk.default_terrain_params()
	tp.use_water   = true
	tp.block_water = blocks.BlockType.Water

	chunks := make([]^chunk.Chunk, WORLD_SIZE_X*WORLD_SIZE_Z, allocator=context.allocator)
	for cz in 0..<WORLD_SIZE_Z {
		for cx in 0..<WORLD_SIZE_X {
			idx := cz*WORLD_SIZE_X + cx
			c := new(chunk.Chunk)
			chunk.chunk_init(c, cx, cz)
			chunk.world_add_chunk(&world, c)
			chunks[idx] = c
		}
	}

    // Initialize the queue for finished chunks
	finished_queue: FinishedChunkQueue

	world_seed : u32 = 1337
	num_workers := si.cpu.logical_cores - 1 
	if num_workers < 1 do num_workers = 1
	
    wa := WorkerArgs{
		chunks         = chunks,
		noise          = &noise,
		seed           = world_seed,
		params         = tp,
		finished_queue = &finished_queue,
	}
	threads = make([dynamic]^thread.Thread)
	defer delete(threads)

	// Spawn workers
	fmt.printf("Spawning %v worker threads for terrain generation...\n", num_workers)
	for _ in 0..<num_workers {
		t := thread.create(worker_proc)
		
		// Set the first element of the user_args array to our arguments pointer.
		t.user_args[0] = &wa

		thread.start(t)
		append(&threads, t)
	}
    cam: rl.Camera3D
	cam.position   = rl.Vector3{50, 10, 0}
	cam.target     = rl.Vector3{ 0, 0,  0}
	cam.up         = rl.Vector3{ 0,  1,  0}
	cam.fovy       = 70
	cam.projection = rl.CameraProjection.PERSPECTIVE
	render.set_camera(cam)
	render.cam_init_from_current()
	render.cam_lock_cursor()

	for !render.should_close() {
		render.cam_update_free(rl.GetFrameTime())

        // Check for '+' key press (Equals key or Keypad Add)
        if rl.IsKeyPressed(rl.KeyboardKey.EQUAL) || rl.IsKeyPressed(rl.KeyboardKey.KP_ADD) {
            view_distance_in_chunks += 1
            if view_distance_in_chunks > MAX_VIEW_DISTANCE {
                view_distance_in_chunks = MAX_VIEW_DISTANCE
            }
        }
        // Check for '-' key press
        if rl.IsKeyPressed(rl.KeyboardKey.MINUS) || rl.IsKeyPressed(rl.KeyboardKey.KP_SUBTRACT) {
            view_distance_in_chunks -= 1
            if view_distance_in_chunks < MIN_VIEW_DISTANCE {
                view_distance_in_chunks = MIN_VIEW_DISTANCE
            }
        }

        current_cam := render.get_camera()

        // Calculate the maximum draw distance based on our setting.
        // We use squared distance to avoid expensive square root calculations.
        max_draw_distance := f32(view_distance_in_chunks) * f32(chunk.CHUNK_SIZE_X)
        max_dist_sq := max_draw_distance * max_draw_distance

		// Check for chunks that have finished generating and build their meshes.
		// We can do a few per frame to avoid causing a super massive lag spike.
		MAX_MESHES_PER_FRAME :: 4
		for _ in 0..<MAX_MESHES_PER_FRAME {
			if finished_chunk, ok := queue_pop(&finished_queue); ok {
                if(finished_chunk.dirty) {
                    chunk.chunk_update_mesh(finished_chunk)
                }
			} else {
				// The queue is empty, no more meshing to do this frame.
				break
			}
		}
        // Get camera matrices
        view_matrix := render.get_camera_view_matrix()
		proj_matrix := rl.GetCameraProjectionMatrix(&current_cam, 16.9)
		view_proj_matrix := proj_matrix * view_matrix
		render.frustum_update(&frustum, view_proj_matrix)

        visible_chunks := 0

        render.begin_frame()
        render.clear_color(18, 18, 22, 255)

        render.begin_world()
			// Opaque Pass
			for _, c in world.chunks {
				aabb := chunk.get_chunk_aabb(c)
                
                chunk_center := aabb.min + ((aabb.max - aabb.min) * 0.5)
                dist_sq := rl.Vector3DistanceSqrt(current_cam.position, chunk_center)
                
                if dist_sq <= max_dist_sq {
                    // passed the distance check, do frustum check.
                    if render.frustum_check_aabb(&frustum, aabb) {
                        chunk.chunk_draw_opaque(c)
                        visible_chunks += 1
                    }
                }
			}

			// Water Pass
			for _, c in world.chunks {
				aabb := chunk.get_chunk_aabb(c)
                chunk_center := aabb.min + ((aabb.max - aabb.min) * 0.5)
                dist_sq := rl.Vector3DistanceSqrt(current_cam.position, chunk_center)

                if dist_sq <= max_dist_sq {
                    if render.frustum_check_aabb(&frustum, aabb) {
                        chunk.chunk_draw_water(c)
                    }
                }
			}

		render.end_world()

		rl.DrawFPS(10, 10)
        
        // Debug info to verify it's working
        total_chunks := len(world.chunks)
        debug_text_str := fmt.tprintf("Visible Chunks: %d / %d", visible_chunks, total_chunks)
        debug_text_cstr := strings.clone_to_cstring(debug_text_str, context.temp_allocator)
        rl.DrawText(debug_text_cstr, 10, 40, 20, rl.LIME)

        render.end_frame()
    }

    // Cleanup threads
    for t in threads {
        thread.join(t)
    }
}