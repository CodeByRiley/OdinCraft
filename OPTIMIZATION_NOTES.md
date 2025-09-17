# OdinCraft optimisation notes

This document records the structural changes applied to the **master** branch of
the OdinCraft project as part of a performance review.  These changes
implement a subset of the recommendations outlined during the code audit and
serve as a foundation for further optimisations.

## Data layout improvements

* **Block array layout:**  The `Chunk` type has been updated to store its
  block data as `[CHUNK_SIZE_Y][CHUNK_SIZE_Z][CHUNK_SIZE_X]`.  Placing the Y
  dimension first means that scanning through blocks in vertical slices
  produces sequential memory accesses, improving cache locality.  The master
  branch already adopted this layout【488341705925426†L25-L33】, so no further
  changes were required.
* **Cached bounding box:**  A new field `aabb: rl.BoundingBox` has been
  added to `Chunk`.  This caches the world‑space bounding box and is
  initialised in `chunk_init` via a call to `get_chunk_aabb`.  This avoids
  recalculating the axis‑aligned bounding box each frame when performing
  frustum culling.

## Neighbour lookup

The original implementation of `get_block_world` used a series of `while`
loops to clamp local coordinates and adjust neighbour chunk coordinates.  This
approach worked but involved multiple iterations per call.  The replacement
implementation eliminates these loops and instead uses integer division and
modulo arithmetic to compute wrapped indices and neighbour offsets in `O(1)`
time.  Out‑of‑bounds Y values still return air immediately.  See the new
implementation in `Chunk.odin` for details.

## API additions

* **chunk.aabb** – A cached `rl.BoundingBox` computed in `chunk_init` to
  support efficient frustum culling.  Functions performing culling should
  reference `c.aabb` rather than recomputing via `get_chunk_aabb`.
* **Updated world initialisation** – `world_init` now accepts an optional
  inset in pixels and initialises the atlas via `blocks.atlas_make`.

## Unimplemented recommendations

Several recommendations from the audit have been noted but are not yet
implemented in this commit:

* **Greedy meshing and preallocation** – The placeholder `chunk_build_geometry`
  currently returns `nil`.  A full implementation should generate geometry
  with back‑face culling, merge adjacent quads with identical textures into
  larger faces, and preallocate dynamic arrays based on worst‑case capacity to
  avoid repeated reallocations.
* **Procedural terrain generation** – The `chunk_generate_perlin` procedure
  remains a stub.  A complete version should precompute 2D height maps,
  generate caves via 3D noise, fill water up to `sea_level` and apply
  topsoil.  Ensure that `c.alive` is checked before performing any work
  to avoid building chunks that were deleted mid‑generation【488341705925426†L186-L208】.
* **Drawing routines** – `chunk_draw_opaque` and `chunk_draw_water` need to
  iterate over `models_opaque`/`models_water` and fall back to the single
  `model`/`water_model` fields when the dynamic arrays are empty.  Proper
  blending state should be set for water【488341705925426†L263-L276】.

These TODOs mark areas for future work.  Additional optimisations such as
greedy meshing, multithreaded generation, and improved noise sampling can be
integrated incrementally.