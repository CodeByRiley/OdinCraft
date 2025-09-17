package helpers

import "core:fmt"
_ :: fmt
GLGetProcAddress :: proc "system"(name: cstring) -> rawptr

when ODIN_OS == .Windows {
    // Manually define the Windows types we need so we don't have to import "core:sys/windows".
    HMODULE :: rawptr
    FARPROC :: rawptr
    
    // --- Use the explicit two-step foreign import pattern ---

    // Step 1a: Tell the linker to link kernel32.lib (CORRECTED)
    foreign import kernel32 "system:kernel32.lib"
    // Step 1b: Declare the procedures we will use from the 'kernel32' block
    foreign kernel32 {
        GetModuleHandleA :: proc "stdcall" (lpModuleName: cstring) -> HMODULE ---
        GetProcAddress   :: proc "stdcall" (hModule: HMODULE, lpProcName: cstring) -> FARPROC ---
    }

    // Step 2a: Tell the linker to link opengl32.lib
    foreign import opengl32 "system:opengl32.lib"
    // Step 2b: Declare the procedure we will use from the 'opengl32' block
    foreign opengl32 {
        wglGetProcAddress :: proc "system"(name: cstring) -> rawptr ---
    }
}
when ODIN_OS == .Linux {
    // Apply the same explicit pattern for Linux for consistency
    foreign import GL "system:GL"
    foreign GL {
        glXGetProcAddress :: proc "system"(name: cstring) -> rawptr ---
    }
}


// A handle to the opengl32.dll library, loaded once.
_opengl32_handle: HMODULE

/**
This is our "smart" loader function.
It uses the functions declared above in the platform-specific foreign blocks.
*/
get_gl_proc_address_smart :: proc "system"(name: cstring) -> rawptr {
    when ODIN_OS == .Windows {
        // 1. Try wglGetProcAddress first (for OpenGL 1.2+ functions)
        ptr := wglGetProcAddress(name)
        if transmute(uintptr)ptr > 3 {
            return ptr
        }

        // 2. If that fails, fall back to GetProcAddress (for OpenGL 1.1 core functions)
        if _opengl32_handle == nil {
            _opengl32_handle = GetModuleHandleA("opengl32.dll")
        }
        return GetProcAddress(_opengl32_handle, name)

    } else when ODIN_OS == .Linux {
        return glXGetProcAddress(name)
    } else {
        #panic("Unsupported OS")
        return nil
    }
}

// --- Initialization and Loading Helpers

_platform_loader: GLGetProcAddress

init_gl_loader :: proc() {
    _platform_loader = get_gl_proc_address_smart
    assert(_platform_loader != nil, "Could not get platform GL proc address loader.")
}

load_gl_proc :: proc(proc_ptr: ^rawptr, name: cstring) -> bool {
    assert(_platform_loader != nil, "gl_loader has not been initialized. Call Init_GL_Loader() first.")
    address := _platform_loader(name)
    if address == nil {
        fmt.eprintf("Failed to load GL procedure: %s\n", name)
        return false
    }
    proc_ptr^ = address
    return true
}