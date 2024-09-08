+++
title = "Good First Issue"
description = "My first open source contribution"
date = 2024-09-08
+++

# TODO:
- [ ] (once finalized) properly capitalize section names & links

It's a goal of mine to make an open source contribution this year. I've had my eyes on [Rerun](https://rerun.io/) for a while, as it's built using [egui](https://github.com/emilk/egui/), which I've used in a number of projects the past few years [^1] [^2]. Rerun's visualizations are fascinating, and like egui, compile to WASM and can run on the web (see the [browser demo](https://rerun.io/viewer) examples). Their [blog post](https://rerun.io/blog/rosbag) on the Rosbag format stood out to me for its quality, reminding me of the home-grown telemetry system we use at 908 Devices and inspiring ideas for future improvements.

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
+         value.to_owned().into_raw_vec_and_offset().0.into(),
```
effectively ignoring the offset by only taking the first element of the tuple returned. I still had the rerun viewer running from my initial build, so I ctrl-C'd out of it on the command line.

# A panic

Let's build the code again with this change. 

Talk about discovering blueprints when displaying the title bar in the UI panicked 

# My (actual) first open source contribution

Talk about finding the documentation error in `ndarray`

# Learnings


[^1]: [RDLA](https://github.com/benliepert/RDLA)
[^2]: [PennyPilot](https://github.com/benliepert/PennyPilot)