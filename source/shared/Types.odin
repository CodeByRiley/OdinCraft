package shared

MeshGeometry :: struct {
    vertsO:  [dynamic]f32, normsO:  [dynamic]f32, uvsO:  [dynamic]f32, colorsO: [dynamic]u8, idxO: [dynamic]u16,
    vertsW:  [dynamic]f32, normsW:  [dynamic]f32, uvsW:  [dynamic]f32, colorsW: [dynamic]u8, idxW: [dynamic]u16,
}

FinishedWork :: struct {
    chunk_ptr: rawptr,
    geometry:  ^MeshGeometry,
}