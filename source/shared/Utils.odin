package shared
import rl "vendor:raylib"

clampf :: proc(x, lo, hi: f32) -> f32 {
    if x < lo do return lo
    if x > hi do return hi
    return x
}

scale_color_u8 :: proc(c: rl.Color, f: f32) -> rl.Color {
    ff := clampf(f, 0.0, 1.0)
    return rl.Color{
        u8(clampf(f32(c.r) * ff, 0.0, 255.0)),
        u8(clampf(f32(c.g) * ff, 0.0, 255.0)),
        u8(clampf(f32(c.b) * ff, 0.0, 255.0)),
        c.a,
    }
}

