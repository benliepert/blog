+++
title = "TBD"
description = "TBD"
date = 2025-2-17
+++

Tags: Rust, WGPU

---

High level topics:
- The graphics stack
    - App
    - GPU abstraction layer
        - wgpu (Rust), bgfx (c++), moderngl (Python)
    - API
        - WebGPU, OpenGL, Vunkan, Metal, D3D12
    - GPU Driver (vendor specific)
    - GPU (HW)
    - wgpu, despite the name, supports ALL the APIs above, not just WebGPU
- pipeline explanation
- shader details
    - reused for similar objects (ie same material)
    - Pipeline:
        - vertex shader (runs first): perspective
            - Applies the following transformations for an object
                - Model: Object space -> World space
                    - Accounts for the object's posiiton/rotation/scale in the world
                - View: World space -> Camera space
                    - Accounts for the camera's position and orientation
                - Projection: Camera space -> Clip space
                    - Simulates the perspective affect by making objects farther from the camera appear smaller by scaling their coordinates accordingly
                    - Results in homogenous (x, y, z, w) (w=depth) coorindates
        - Mid point (NOT part of a shader)
            - Primitive Assembly: assemble vertices into primitives
            - Clipping
                - Get rid of primitives that are outside the camera view (frustum culling)
                - Objects that are on the boundary are "clipped" or cut so that the pieces that are out of view aren't drawn
                - produces points in "clip space"
            - Perspective Division
                - Takes the homogenized coordinates from clip space to normalized device coordinates (NDC)
                - NDC coordinates are used to determine which pixels (fragments) on the screen are covered by primitives
            - Viewport transformation
                - Transform NDC to "screen space" or "window coordinates" which is a physical display
            - Rasterization: convert primitives into pixels that are on the screen
                - Primitive setup:
                    - determine which primitives are visible and need to be rasterized
                - Scan conversion:
                    - calculate which pixels are covered by each primitive
                - Interpolation:
                    - a vertex outputs data at set vertices. But there is space between these that needs values!
                    - this is the mathematical process to calculate the following things for points between vertices:
                        - texture coordinates
                        - normals (for lighting)
                        - colors
                    - basically a weighted avg calculation
                - Fragment generation:
                    - Creates a fragment for each pixel covered by the primitive and assigns it the interpolated data from above
                    - It knows which pixels are covered because of viewport transformation
                    - Passed to fragment shader
        - fragment shader (runs second)
            - Operates on fragment (pixels)
            - Computes final color & other attributes
            -
        - Per-fragment operations (typical order):
            - Pixel ownership test
                - Don't render pixels that are obscured by another window/off screen
            - Scissor test:
                - Rendering a HUD, where only a specific screen portion should be updated
            - Stencil testing: discard fragments based on a stencil buffer
                - Masking, outlining, etc
            - Depth testing: discard fragments behind other fragments
                - Almost always enabled for 3D rendering
            - Blending: Combine the fragment's color with the color already in the framebuffer
                - Transparency, special affects, color blending
            - Dithering:
                - Apply noise to simulate higher color depth, reduce banding
                - used to smooth gradients in a low-color-depth display
            - Logic operations
                - Rare. AND/OR/XOR fragment color with the framebuffer color