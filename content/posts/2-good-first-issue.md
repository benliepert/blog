+++
title = "Good First Issue"
description = "My first open source contribution"
date = 2024-09-08
+++

# TODO:
- [ ] (once finalized) properly capitalize section names & links
    - Maybe call Learnings "closing" or "conclusion"
- [ ] make sure you revert/don't commit config.toml change before publishing

It's a goal of mine to make an open source contribution this year. I've had my eyes on [Rerun](https://rerun.io/) for a while, as it's built using [egui](https://github.com/emilk/egui/), which I've used in a number of projects the past few years [^1] [^2]. Rerun's visualizations are fascinating and, like egui, compile to WASM and can run on the web (see the [browser demo](https://rerun.io/viewer) examples). Their [blog post](https://rerun.io/blog/rosbag) on the Rosbag format stood out to me for its quality, reminding me of the home-grown telemetry system we use at 908 Devices and inspiring ideas for future improvements.

## Sections
- [Finding an Issue](#finding-an-issue)
- [Getting started](#getting-started)
- [A naive solution](#a-naive-solution)
- [A panic](#a-panic)
- [My (actual) first open source contribution](#my-actual-first-open-source-contribution)
- [Learnings](#learnings)

# Finding an Issue
At the time of writing, there were 959 open issues in the [Rerun repository](https://github.com/rerun-io/rerun) and 13 open with the "good first issue" label. Only a few hadn't already received attention, including [#7157 Update `ndarray`](https://github.com/rerun-io/rerun/issues/7157). Cool, a major version bump for a dependency that deprecated some functions.

 <!-- This certainly won't require me to refactor macros on a tensor data structure ☺️. -->

# Getting Started
First I wanted to get the project building, bump the `ndarray` version, and see what goes wrong. Rerun has good developer documentation, so despite being a much larger and more complex Rust project than I've ever worked on, it was fairly quick to get up and running.

I updated the `ndarray` version from 0.15 to 0.16 and rebuilt. There were a couple deprecations, but I'll focus on the deprecation of `Array::into_raw_vec()` in favor of `Array::into_raw_vec_and_offset()`.

# A naive solution
The function is used in a macro on `TensorData`. I haven't written more than the simplest Rust macros, nor do I actually know what a tensor is despite having heard of it in e.g. TensorFlow. Well, the new function returns a tuple containing the raw vector and an offset (whatever that is), and the existing code isn't using an offset, so it must be safe to ignore! I changed the code to
```diff
-     buffer: TensorBuffer::$variant(value.to_owned().into_raw_vec().into()),
+     buffer: TensorBuffer::$variant(
+         value.to_owned().into_raw_vec_and_offset().0.into()),
```
effectively ignoring the offset by only taking the first element of the tuple returned. I still had the rerun viewer running from my initial build, so I ctrl-c'd out of it on the command line.

# A panic

Let's build the code again with this change. 

```s
...
[2024-09-04T17:08:46Z DEBUG re_viewer_context::store_hub] Cloning Welcome screen as f1690a39-5c05-430e-a022-976e2a49fa9c the active blueprint for Welcome screen to Welcome screen

thread 'main' panicked at 'assertion failed: size.x >= 0.0 && size.y >= 0.0'
egui/src/layout.rs:395
...
```
Uh oh. This persisted after a `cargo clean` and a rebuild, so I suspected Rerun was storing state on disk and loading it in as the app started. This state was probably corrupted by my impolite ctrl-c. It turns out Rerun stores UI state in something called a blueprint, I added a print statement to the code that loads blueprints to find the path to the file, and deleted it. This resolved the panic. 

I should have preserved the file and created a ticket for reproduction. The panic itself was down in the egui layout code, and traced back up to adding a clickable website link on the Rerun top panel. As far as I could tell, the image itself was sized fine, but it was being placed in an area of negative size.

# Solving continued
With the panic resolved, I opened a PR. I heard back from Emil (Rerun co-founder & egui creator) within a day:

> We shouldn't ignore the offset. If it is non-zero, we may have a problem.
> We should at least return `TensorCastError::NotContiguousStdOrder` in that case.
>
> However, ideally we should handle arrays that are not in standard layout (and/or with an offset) by calling .iter().collect() instead of bailing.
>
> — <cite>emilk</cite>

Okay, so nonzero offsets are a problem. But I still didn't understand what an offset was here. Interestingly, there was an example of using .iter().collect() on a _different_ macro in this file, which I'll explain in a moment. Overall, his comment made sense at a high level, but I realized I'd need to dig into the unfamiliar context of this change to do it correctly.


# Testing
I needed to figure out whether the offset can be non-zero even if the array was a standard layoyut. Rerun is huge, so I wanted to avoid editing a main file somewhere with some test code and having to rebuild a ton of stuff when I really only needed to play with the `re_types` crate. So I created a binary crate and added a dependency to my local version of the `re_types` crate:
```toml
[dependencies]
re_types = { path = "../rerun/crates/store/re_types"}
```
Now I can play around with the new macros with minimal churn.

I eventually arrived at the following test code to prove that an array can have a standard layout but a nonzero offset. The key here is slicing into an existing owned array - if you make a slice and then take a clone, the offset will reset to zero.
```rust
use ndarray::{Array, s};
// create a 4 x 4 array with the numbers [0, 15]
let array = Array::from_iter(0..16).into_shape_with_order((4, 4)).unwrap();
// slice off the first row. We're only looking at the last 3 rows
let sliced_array = array.slice_move(s![1.., ..]);
assert!(sliced_array.is_standard_layout());
let (_, offset) = sliced_array.into_raw_vec_and_offset();
assert!(offset.unwrap() > 0);
```

# My (actual) first open source contribution

Talk about finding the documentation error in `ndarray`

# Learnings

I went into this fix with a false sense of security. Rerun as a whole, let alone Tensors and macros, were unfamiliar, and I expected to keep them at arms length. Increment a version, read the docs to make sure I replace the necessary functions correctly, make sure the tests pass, and move on. This still turned out to be a great first issue as it was well matched to my current skill level while still being challenging.

A big thanks to Emil for egui, Rerun, and his prompt, intelligent responses despite my inexperience in open source. I'm sure I'll be back to contribute more.


[^1]: [RDLA](https://github.com/benliepert/RDLA)
[^2]: [PennyPilot](https://github.com/benliepert/PennyPilot)