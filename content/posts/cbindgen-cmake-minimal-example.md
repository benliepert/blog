+++
title = "Calling Rust from C++: A minimal example"
description = "Calling Rust from C++, cross compilation with Docker"
date = 2024-08-27
+++

Tags: C++, Rust, Docker, CMake, cbindgen

---

Recently, I realized after almost 2 years of tinkering with Rust, I hadn't played with the FFI to C or C++. This post covers a minimal example including cross-compilation via Docker. I plan to focus on the build configuration, as I haven't written any 'real' Rust code to call from C++, and there are lots of cbindgen examples online. This will be a quick post to get the foundational build elements working together. Tyler Weaver wrote a more comprehensive series [here](https://tylerjw.dev/posts/rust-cpp-interop/).

> The complete source code for this post can be found [on Github](https://www.github.com/benliepert/post-1)

## Sections
- [Rust](#rust)
- [C++](#c)
- [CMake](#cmake)
- [Build](#build)
- [Run](#run)

---
# Rust
Let's start with a Rust lib crate called `rust_toy`: `cargo new --lib rust_toy`.

```rust
// rust_toy/src/lib.rs
#[no_mangle]
pub extern "C" fn rust_function() {
    println!("Hello World from Rust!");
}
```
[cbindgen](https://github.com/mozilla/cbindgen) is a tool that generates (unsafe) C bindings from Rust code. You can use its CLI or call it in a `build.rs` script for seamless integration with `cargo`. We're going to use it via `build.rs`, so let's include it as a build dependency.
```toml
# rust_toy/Cargo.toml
[package]
name = "rust_toy"
version = "0.1.0"
edition = "2021"

[lib]
# Create a c/cpp dynamic library. No rust specific metadata
crate-type = ["cdylib"]
# For a static library, use:
# crate-type = ["staticlib"]

[dependencies]

[build-dependencies]
# We're going to generate bindings in build.rs
cbindgen = "0.24.0"
```
```rust
// rust_toy/build.rs
extern crate cbindgen;
use std::env;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();

    cbindgen::Builder::new()
      .with_crate(crate_dir)
      // Other language options are 'C' and 'Cython'
      .with_language(cbindgen::Language::Cxx)
      .generate()
      .expect("Unable to generate bindings")
      // This is the file where the bindings will be generated
      .write_to_file("include/rust_toy.h");

    // cargo will rerun this file if the lib file changes
    println!("cargo:rerun-if-changed=src/lib.rs");
}
```
One curveball for my use case is that I want to cross compile for armv7. So we need to tell cargo to use the relevant linker when compiling for the armv7 target we'll be using:
```toml
# rust_toy/.cargo/config.toml
[target.armv7-unknown-linux-gnueabihf]
linker = "arm-linux-gnueabihf-g++"
```
Note that this is a new file, not the usual `Cargo.toml`. This is a quirk of `cargo`'s configuration management. You can read about others [here](https://towardsdatascience.com/nine-rust-cargo-toml-wats-and-wat-nots-1e5e02e41648).

> The `cbindgen::Language` you use should match the linker (`Cxx` -> g++, `C` -> gcc, etc). And this should match the language you're intending to use Rust from. Even if you have a cpp file that really only uses the C subset of the language, if you're compiling using a C++ compiler you need the Rust build config to match (otherwise you'll spend hours debugging the simple mismatch, and end up writing a blog post about it).
---
# C++
We need some C++ code to call the Rust. Let's make something really simple:
```cpp
// test.cpp

// cbindgen will create this file for us
// we'll make sure it's accessible via cmake
#include "rust_toy.h"
int main() {
    rust_function();
    return 0;
}
```
---
# CMake
I'm not a cmake expert, so I won't go too deep into the configuration. Generally speaking, you'll want something like this:
```cmake
cmake_minimum_required(VERSION 3.16)

# Cross compilation setup ---------------------------------
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armhf)

# which compilers to use for C++ cross-compilation
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)

# where is the target environment located?
set(CMAKE_FIND_ROOT_PATH /usr/lib/arm-linux-gnueabihf/)
# ---------------------------------------------------------

# Build artifacts will go in these locations
# Not necessary for this simple project, but useful when you have more
# artifacts and want to copy them all to a runtime dockerfile easily
SET(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
SET(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

PROJECT(tester)

# The name of the C++ file we're building
SET(SOURCES test.cpp)

# Rust specific setup -------------------------------------
# Where is the crate we're building?
set(RUST_PROJECT_DIR "${CMAKE_SOURCE_DIR}/rust_toy")
# The profile to use when building the crate
set(RUST_BUILD_MODE "release")
# The shared object (so) we're creating
set(RUST_SO_NAME "librust_toy.so")
# Where is the object initially created?
set(RUST_SO "${RUST_PROJECT_DIR}/target/armv7-unknown-linux-gnueabihf/${RUST_BUILD_MODE}/${RUST_SO_NAME}")
# The common location it will live
set(RUST_SO_COMMON "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/${RUST_SO_NAME}")

add_custom_command(
    OUTPUT ${RUST_SO_COMMON}
    # Build the rust code
    COMMAND ${CMAKE_COMMAND} -E env cargo build --${RUST_BUILD_MODE}
             --manifest-path ${RUST_PROJECT_DIR}/Cargo.toml
             --target armv7-unknown-linux-gnueabihf
    # Copy the library to a common location
    COMMAND ${CMAKE_COMMAND} -E copy ${RUST_SO}
            ${RUST_SO_COMMON}
    WORKING_DIRECTORY ${RUST_PROJECT_DIR}
    COMMENT "Building Rust project with cargo"
    VERBATIM
)

# Add a target for the Rust library (this will ensure the Rust build happens)
add_custom_target(rust_build ALL
    DEPENDS ${RUST_SO_COMMON}
)

# so we can seamlessly link against this lib, we tell cmake to find it where we copied it (where the other libs live)
add_library(rust_toy SHARED IMPORTED)
set_target_properties(rust_toy PROPERTIES
    IMPORTED_LOCATION ${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/${RUST_SO_NAME}
)
# ---------------------------------------------------------

# The executable we're building, and its sources
ADD_EXECUTABLE(test ${SOURCES})
# Our exe depends on the rust_build custom target, which will build the .so we need
add_dependencies(test rust_build)

# Link against the rust library, since we use it in test.cpp
TARGET_LINK_LIBRARIES(test rust_toy)

TARGET_INCLUDE_DIRECTORIES(test PRIVATE ${RUST_PROJECT_DIR}/include)
```
It's certainly a chore writing CMake after using `cargo`, but that's not the point of this post.

---
## Build
I'm using `docker` to build, as I can't natively compile for armv7. A common way to divy this up is with:
- A build container, which contains all your build dependencies, and is responsible for building a deployable executable/libraries
- A runtime container, which contains runtime dependencies and your executable/libraries.

This can be accomplished using different stages in Docker (if you've seen `FROM xyz as builder`, that's a stage), but I split it into 2 dockerfiles for clarity.

```dockerfile
# Dockerfile.local_build

FROM torizon/debian-cross-toolchain-armhf:3-bookworm

# Add build dependencies
RUN apt-get update && dpkg --add-architecture armhf && \
	apt-get install -y --no-install-recommends \
        cmake \
        gcc \
        libc6-dev \
	&& apt-get clean && apt-get autoremove && rm -rf /var/lib/apt/lists/* 

USER torizon

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
        && . $HOME/.cargo/env \
        && rustup target add armv7-unknown-linux-gnueabihf

# make our rust builds colorful
ENV CARGO_TERM_COLOR=always

WORKDIR /build
# The actual build command. Configure and run cmake using all our CPUs
# Note that sourcing cargo is necessary to have access to cargo.
# That isn't an issue if you use a 'Rust' base docker container
ENTRYPOINT . "$HOME/.cargo/env" && \
    cmake . -B build -DCMAKE_BUILD_TYPE=Debug && \
    cd build && make -j $(nproc)
```
Notice that this image definition doesn't contain any of our code. That's because we're going to map the source code in with a volume mount at runtime. The build will be performed against our local directory, meaning build artifacts will be preserved between builds and there's no costly copy operation.

---
# Run 
You could copy the `test` executable and `librust_toy.so` directly to an armv7 system to run it, but I don't have one so I'm going to use a docker container. Just like an actual arm system, we only need to copy the final C++ executable and the Rust shared library
```dockerfile
# Dockerfile.local_run

FROM --platform=linux/arm/v7 torizon/debian:3-bookworm

USER torizon

# Copy the main executable in
COPY build/bin/test /app/test
# Copy all libraries in. Our exe needs these since it was linked against it
COPY build/lib/* /usr/lib/

# Tell the main executable to run automatically
ENTRYPOINT "/app/test"
```
Now use the following commands to build and run the application locally!
```sh
# Build the container required to build the test app
docker build -f Dockerfile.local_build -t build-image .

# Build the test application. Note the current directory mount
# Our CMake command in the ENTRYPOINT of Dockerfile.local_build
# is expecting the source to be here
docker run -v $(pwd):/build build-image

# Build the final runtime container
docker build -f Dockerfile.local_run -t run-image .

# Run the app locally inside of the runtime container
docker run --rm run-image
```
I've added a justfile to the repository as well if you'd like to use the [`just`](https://github.com/casey/just) command runner.
You should see the following output. I got a warning since I'm running on an x86_64 machine, but you wouldn't see this when running on an armv7 platform like a Raspberry Pi.
```sh
WARNING: The requested image's platform (linux/arm/v7) does not match the detected host platform (linux/amd64/v3) and no specific platform was requested
Hello World from Rust!
```

