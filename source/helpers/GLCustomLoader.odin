package helpers

// We still need to import the OpenGL package for constants like TEXTURE_3D, RED, etc.
// Ensure you have the correct import path for your project setup.
import _ "vendor:OpenGL"

// This file assumes the existence of the following procedures from your GLContext.odin file:
// init_gl_loader :: proc()
// load_gl_proc   :: proc(proc_ptr: ^rawptr, name: cstring) -> bool


// ---------------- C-style OpenGL Function Pointer Types ----------------
// Signatures now use primitive Odin types (i32, u32) as per the documentation.

PFNGLGENTEXTURES_PROC    :: proc "c" (n: i32, textures: [^]u32)
PFNGLDELETETEXTURES_PROC :: proc "c" (n: i32, textures: [^]u32)
PFNGLBINDTEXTURE_PROC    :: proc "c" (target: u32, texture: u32)
PFNGLTEXIMAGE3D_PROC     :: proc "c" (target: u32, level: i32, internalformat: i32, width: i32, height: i32, depth: i32, border: i32, format: u32, type: u32, pixels: rawptr)
PFNGLTEXPARAMETERI_PROC  :: proc "c" (target: u32, pname: u32, param: i32)

// ---------------- Global Function Pointers (Private to this file) ----------------
_GenTextures:    PFNGLGENTEXTURES_PROC
_BindTexture:    PFNGLBINDTEXTURE_PROC
_TexImage3D:     PFNGLTEXIMAGE3D_PROC
_TexParameteri:  PFNGLTEXPARAMETERI_PROC
_DeleteTextures: PFNGLDELETETEXTURES_PROC


// ---------------- Initialization Procedure ----------------

gl_custom_init :: proc() -> bool {
    ok := true
    // MODIFIED: Call the newly renamed public procedure
    ok = ok && load_gl_proc(cast(^rawptr)&_GenTextures,   "glGenTextures")
    ok = ok && load_gl_proc(cast(^rawptr)&_BindTexture,   "glBindTexture")
    ok = ok && load_gl_proc(cast(^rawptr)&_TexImage3D,    "glTexImage3D")
    ok = ok && load_gl_proc(cast(^rawptr)&_TexParameteri, "glTexParameteri")
    ok = ok && load_gl_proc(cast(^rawptr)&_DeleteTextures, "glDeleteTextures")
    return ok
}


// ---------------- Public Wrapper Procedures ----------------
// These are the safe, public functions your application will call.

GL_GenTextures :: proc(n: i32, textures: [^]u32) {
    assert(_GenTextures != nil, "OpenGL function glGenTextures was not loaded!")
    _GenTextures(n, textures)
}

GL_BindTexture :: proc(target: u32, texture: u32) {
    assert(_BindTexture != nil, "OpenGL function glBindTexture was not loaded!")
    _BindTexture(target, texture)
}

GL_DeleteTextures :: proc(n: i32, textures: [^]u32) {
    assert(_DeleteTextures != nil, "OpenGL function glDeleteTextures was not loaded!")
    _DeleteTextures(n, textures)
}

GL_TexImage3D :: proc(target: u32, level: i32, internalformat: i32, width: i32, height: i32, depth: i32, border: i32, format: u32, type: u32, pixels: rawptr) {
    assert(_TexImage3D != nil, "OpenGL function glTexImage3D was not loaded!")
    _TexImage3D(target, level, internalformat, width, height, depth, border, format, type, pixels)
}

GL_TexParameteri :: proc(target: u32, pname: u32, param: i32) {
    assert(_TexParameteri != nil, "OpenGL function glTexParameteri was not loaded!")
    _TexParameteri(target, pname, param)
}