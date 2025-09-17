package threading

import thread  "core:thread"
import helpers "../helpers"
import sync  "core:sync"
import chunk "../chunk"
import "../shared"

// Array of threads
threads: [dynamic]^thread.Thread

// NOTE: The thread_purgatory has been removed as it was the source of a crash.
// thread_purgatory: [dynamic]^chunk.Chunk 

RemeshJobQueue :: struct {
    items: [dynamic]^chunk.Chunk,
    mutex: sync.Mutex,
}

RemeshWorkerArgs :: struct {
    job_q: ^RemeshJobQueue,
    out_q: ^FinishedChunkQueue,
    running: ^bool,
}

FinishedChunkQueue :: struct {
    work:  [dynamic]shared.FinishedWork,
    mutex: sync.Mutex,
}

WorkerArgs :: struct {
    chunks_to_generate: [dynamic]^chunk.Chunk,
    start:   int,
    stride:  int,
    noise:           ^helpers.Perlin,
    seed:            u32,
    params:          chunk.TerrainParams,
    finished_queue: ^FinishedChunkQueue,
}

remesh_push_unique :: proc(q: ^RemeshJobQueue, c: ^chunk.Chunk) {
    if c == nil do return
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)
    for it in q.items {
        if it == c { return }
    }
    append(&q.items, c)
}

remesh_pop :: proc(q: ^RemeshJobQueue) -> (^chunk.Chunk, bool) {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)
    if len(q.items) == 0 { return nil, false }
    c := q.items[0]
    ordered_remove(&q.items, 0)
    return c, true
}

queue_push :: proc(q: ^FinishedChunkQueue, work: shared.FinishedWork) {
    sync.mutex_lock(&q.mutex)
    defer sync.mutex_unlock(&q.mutex)
    append(&q.work, work)
}

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

// CORRECTED: This now matches the logic of your remesh_worker_proc
worker_proc :: proc(t: ^thread.Thread) {
    args := (^WorkerArgs)(t.user_args[0])
    for i := args.start; i < len(args.chunks_to_generate); i += args.stride {
        c := args.chunks_to_generate[i]
        
        if !sync.atomic_load(&c.alive) { continue }

        // 1. Generate the block data
        chunk.chunk_generate_perlin(c, args.noise, args.seed, args.params)
        
        if !sync.atomic_load(&c.alive) { continue }

        // 2. Calculate the lighting for the new chunk
        chunk.chunk_rebuild_lighting(c)

        // 3. Build the simplified geometry
        geometry := chunk.chunk_build_geometry(c)

        // 4. Create the raw data for the 3D textures
        opacity_raw := chunk.chunk_create_raw_gpu_data(c)

        // 5. Push everything to the main thread
        if sync.atomic_load(&c.alive) {
            work := shared.FinishedWork{
                chunk_ptr    = rawptr(c),
                geometry     = geometry,
                opacity_data = opacity_raw,
            }
            queue_push(args.finished_queue, work)
        } else {
            // Cleanup if it died mid-process
            chunk.free_geometry(geometry)
            delete(opacity_raw)
        }
    }
}

// Mesh-only worker (Your version was already correct)
remesh_worker_proc :: proc(t: ^thread.Thread) {
    args := (^RemeshWorkerArgs)(t.user_args[0])
    for sync.atomic_load(args.running) {
        c, ok := remesh_pop(args.job_q)
        if !ok {
            thread.yield()
            continue
        }
        if c == nil || !sync.atomic_load(&c.alive) { continue }

        chunk.chunk_rebuild_lighting(c)
        geo := chunk.chunk_build_geometry(c)
        opacity_raw := chunk.chunk_create_raw_gpu_data(c)
        
        if sync.atomic_load(&c.alive) {
            work := shared.FinishedWork{
                chunk_ptr    = rawptr(c),
                geometry     = geo,
                opacity_data = opacity_raw,
            }
            queue_push(args.out_q, work)
        } else {
            chunk.free_geometry(geo)
            delete(opacity_raw)
        }
    }
}