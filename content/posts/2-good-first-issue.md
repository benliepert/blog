+++
title = "Good First Issue"
description = "My first open source contribution"
date = 2024-09-30
+++

# TODO:
- [ ] (once finalized) properly capitalize section names & links
    - Maybe call Learnings "closing" or "conclusion"
- [ ] make sure you revert/don't commit config.toml change before publishing

It's been a goal of mine to make an open source contribution this year. I've had my eyes on [Rerun](https://rerun.io/) for a while, as it's built using [egui](https://github.com/emilk/egui/), which I've used in a number of projects the past few years [^1] [^2] [^3]. Rerun's visualizations are fascinating and, like egui, compile to WASM and can run on the web (see the [browser demo](https://rerun.io/viewer) examples). Their [blog post](https://rerun.io/blog/rosbag) on the Rosbag format stood out to me for its quality, reminding me of the home-grown telemetry system we use at 908 Devices and inspiring ideas for future improvements.

## Sections
- [Finding an Issue](#finding-an-issue)
- [Getting Started](#getting-started)
- [A Naive Solution](#a-naive-solution)
- [A Panic](#a-panic)
- [Solving Continued](#solving-continued)
- [Validation](#validation)
- [Code Changes](#code-changes)
- [Adding Tests](#adding-tests)
- [Conclusion](#conclusion)

# Finding an Issue
At the time of writing, there were 959 open issues in the [Rerun repository](https://github.com/rerun-io/rerun) and 13 open with the "good first issue" label. Only a few hadn't already received attention, including [#7157 Update `ndarray`](https://github.com/rerun-io/rerun/issues/7157). Cool, a major version bump for a dependency that deprecated some functions.

 <!-- This certainly won't require me to refactor macros on a tensor data structure ☺️. -->

# Getting Started
First I wanted to get the project building, bump the `ndarray` version, and see what goes wrong. Rerun has good developer documentation, so despite being a much larger and more complex Rust project than I've ever worked on, it was fairly quick to get up and running.

I updated the `ndarray` version from 0.15 to 0.16 and rebuilt. There were a couple deprecations, but I'll focus on the deprecation of `Array::into_raw_vec()` in favor of `Array::into_raw_vec_and_offset()`.

# A Naive Solution
The function is used in a macro on `TensorData`. I haven't written more than the simplest Rust macros, nor did I really know what a tensor is despite having heard of it in e.g. TensorFlow. Well, the new function returns a tuple containing the raw vector and an offset, and the existing code isn't using an offset, so it must be safe to ignore! I changed the code to:
```diff
-     buffer: TensorBuffer::$variant(value.to_owned().into_raw_vec().into()),
+     buffer: TensorBuffer::$variant(
+         value.to_owned().into_raw_vec_and_offset().0.into()),
```
effectively ignoring the offset by only taking the first element of the tuple returned. I still had the rerun viewer running from my initial build, so I ctrl-c'd out of it on the command line.

# A Panic

Let's build the code again with this change. 

```s
...
[2024-09-04T17:08:46Z DEBUG re_viewer_context::store_hub] Cloning Welcome screen as f1690a39-5c05-430e-a022-976e2a49fa9c the active blueprint for Welcome screen to Welcome screen

thread 'main' panicked at 'assertion failed: size.x >= 0.0 && size.y >= 0.0'
egui/src/layout.rs:395
...
```
Uh oh. This persisted after a `cargo clean` and a rebuild, so I suspected Rerun was storing state on disk and loading it in as the app started. This state was probably corrupted by my impolite ctrl-c. It turns out Rerun stores UI state in something called a blueprint, which decouples data visualization from the data itself. I added a print statement to the code that loads blueprints to find the path to the blueprint file, and deleted it. This resolved the panic. 

> I should have preserved the file and created a ticket for reproduction. The panic itself was down in the egui layout code, and traced back to adding a clickable image containing a website link on the top panel. As far as I could tell, the image itself was sized ok but was being placed in an area of negative size.

# Solving Continued
With the panic resolved, I opened a PR. I heard back from Emil (Rerun co-founder & egui creator) within a day:

> We shouldn't ignore the offset. If it is non-zero, we may have a problem.
> We should at least return `TensorCastError::NotContiguousStdOrder` in that case.
>
> However, ideally we should handle arrays that are not in standard layout (and/or with an offset) by calling .iter().collect() instead of bailing.
>
> — <cite>emilk</cite>

This was a good insight - we could do better than simply preserving the existing behavior, which returned an error for non-standard layout ndarrays.

# Definitions
Before moving forward, it's crucial to answer the following questions:

- Standard Layout:
- Why did he suggest iter().collect()?
    - because this preserves the logical order despite what may be an inconsistent underlying order in memory {a non-zero offset implies we can't pull directly from memory - WHY?}
- Row major vs column major?
What's slicing?

What's an offset?

Simply speaking - the index of the first logical element in the underlying vector containing the array. Take the following example:
```rs
let v = vec![1,2,3]; // offset 0. The first element (1) is at index 0 + 0 (the offset)
```
However, things get more complicated in a library like `ndarray` that needs to represent n-dimensional arrays while striving for performance. When _slicing_ an array, `ndarray` doesn't clone all of the data again, but rather retains a pointer to the first element in the raw buffer where the data already lives. Given an array of elements with type `T`, the offset can be computed by subtracting a pointer to the start of the raw buffer from the pointer to the first element, and dividing by the size of `T`. This optimization ensures that slicing is zero-copy and retains O(1) extraction of the raw buffer.

There are other related ways to end up with a non-zero offset, but the point is it's possible regardless of what underlying memory layout is used. This possibility revealed a bug in a `TryFrom<Array>` implementation for `TensorData`, which was blindly casting the raw buffer regardless of whether there was an offset. In practice, this could cause data sliced off an `Array` to magically reappear when converting it to `TensorData` using this trait!

# Validation
To prove programmatically that the offset can be non-zero even if the array was a standard layout, I started by creating a binary crate that depended on my local version of the `re_types` crate. This avoids re-building/linking Rerun's many dependencies while developing the fix.
```toml
# Cargo.toml in my new binary crate
[dependencies]
re_types = { path = "../rerun/crates/store/re_types"}
```
Now I can play around with the modified macros with minimal churn!

Given what we know from the last section, slicing should produce a non-zero offset. The key here is slicing into an existing owned array - if you make a slice and then take a clone, the offset will reset to zero as a new raw buffer is allocated containing _only_ the sliced data.
```rust
use ndarray::{Array, s};

// create a 4 x 4 array with the numbers [0, 15]
// [0, 1, 2, 3,
//  4, 5, 6, 7,
//  8, 9, 10, 11,
//  12, 13, 14, 15]
// Array uses std layout by default
let array = Array::from_iter(0..16).into_shape_with_order((4, 4)).unwrap();

// slice off the first row. We're only looking at the last 3 rows
// but the raw buffer stays the same - we just skip the first 4 elements (this is the offset)
// [4, 5, 6, 7,
//  8, 9, 10, 11,
//  12, 13, 14, 15]
let sliced_array = array.slice_move(s![1.., ..]);
// layout should be identical, since the raw buffer is the same
assert!(sliced_array.is_standard_layout());

let (_, offset) = sliced_array.into_raw_vec_and_offset();
let offset = offset.unwrap();
assert!(offset > 0);
assert!(offset == 4);
```

> While investigating the above code, I noticed the documentation for `ndarray::Array::into_raw_vec_and_offset()`, said the function would return 0 if the array was empty. That didn't make sense - when would the function return `None` then? It turns out the function _does_ return `None` if the array is empty, as the documentation for a helper function confirmed. I created a [PR](https://github.com/rust-ndarray/ndarray/pull/1432) which was promptly merged. So technically, _this_ was my first issue...

# Code Changes
Now that I'd proven we could have a standard layout array with nonzero offset, it was time to update the macros that used the outdated functions and add test cases.

The deprecated functions were used in areas that converted an `Array` to Rerun's `TensorData`. We essentially need to get a logically-ordered `Vec<T>` from the `Array`. My changes follow one of 2 branches in this context:

1. The `Array` is standard layout. `into_raw_vec_and_offset()` guarantees that the logical element order (`.iter()`) matches the internal storage order in this case. This means that we can simply chop off the front of the `Array`s raw vector, until the offset, and return the vector that remains. This takes O(1) time.
2. The `Array` is in a nonstandard layout. There's no shortcut here, we must collect the iterator into a vector. This takes O(n) time.

# Adding Tests
I added 2 tests to cover the new cases:
1. Create a row major and column major version of the same underlying data. Convert both to `TensorData`, and ensure the results match.
2. Same as above, but with a nonzero offset.

I used the same underlying data for both tests, so it's implied that all `TensorData`s match. Looking back, I would have combined the cases for some extra robustness. I think it's technically possible to write a broken implementation that still passes both tests, though I'm not worried about that happening accidentally.

# Conclusion

This turned out to be a great first issue as it was well matched to my current skill level while still being challenging and pushing me to learn a few things outside of my comfort zone.

A big thanks to Emil for egui, Rerun, and his prompt, intelligent responses despite my inexperience in open source. I'm sure I'll be back to contribute more.


[^1]: [RDLA](https://github.com/benliepert/RDLA)
[^2]: [PennyPilot](https://github.com/benliepert/PennyPilot)
[^3]: [3DLA](https://github.com/benliepert/3dla)
