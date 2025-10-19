+++
title = "Don't Hold Me Back: crates.io Pre-1.0 Dependency Analysis"
description = "An analysis of pre-1.0 dependencies on crates.io and their potential impact on Rust ecosystem stability."
date = 2025-10-13
+++

I recently read [this](https://ranger-ross.github.io/blog/more-stable-ecosystem/) blog post by Ross Sullivan that makes an argument for crate authors to stabilize (i.e. publish a version >= 1.0.0). But one line stood out to me in particular:
> If some key crates hit 1.0.0 it would allow entire ecosystems of crates to stabilize.

Ross didn't provide any more details, though it's a totally reasonable statement. The following is my investigation to better understand this statement. Thanks for nerd sniping me, Ross.

# Definition

Ross makes good arguments for _why_ crates should prefer to stabilize, but I'd like to define the _what_ of the issue at play. I recommend reading his blog post (it's pretty short) though I'll cover some of the basics below.

Rust crates (libraries) tend to follow [semantic versioning](https://semver.org/) or 'SemVer', meaning they have a version number of the form `MAJOR.MINOR.PATCH`. The tenets of this scheme are to increment the:
> 1. MAJOR version when you make incompatible API changes
> 2. MINOR version when you add functionality in a backward compatible manner
> 3. PATCH version when you make backward compatible bug fixes

But there's a crucial additional note in the SemVer specificaion:
> 4. Major version zero (0.y.z) is for initial development. Anything MAY change at any time. The public API SHOULD NOT be considered stable.

Thus, any crate that's "Pre-1.0", with a major version of 0, is "unstable". There may be breaking changes at any time. A breaking change in crate A may require "dependents" (crates that depend on crate A) to update themselves (in order to update the version of crate A they depend on). In practice, an example of this would be changing a public function name - now dependents need to change that function name as well.

Side note: I highly recommend Predrag Gruevski's [cargo-semver-checks](https://github.com/obi1kenobi/cargo-semver-checks) for help adhering to semantic versioning in practice. There are a lot of edge cases!

Thus, when a crate is unstable (Pre-1.0), its dependents may be be wary to _themselves_ stabilize. Take crate A, v0.1, that depends on crate B, also v0.1. Any update to crate B may be breaking. If crate B is essential to crate A’s functionality, crate A may delay stabilization until crate B stabilizes, since ongoing changes in crate B create uncertainty about how much work crate A will need to do to stay compatible. Ross' post goes into more detail about this conundrum.

# Questions

Recall Ross' statement:
> If some key crates hit 1.0.0 it would allow entire ecosystems of crates to stabilize.

My initial questions in response were "what are these key crates?" and "what do the ecosystems they're holding back look like?"

There's nuance in defining "key" - is it number of dependents? number of downloads? GitHub stars? Some combination of factors? What if the crate was very popular 5 years ago, but is now deprecated or unmaintained?

Crates contained in the "ecosystem" being held back are subject to similar questions - I wouldn't argue that a crate should stabilize solely so that a depededent that nobody downloads can stabilize as well. Furthermore, we shouldn't include dependents if they don't even _use_ the parent crate.

For my initial investigation, I focused on the crates with the most dependents as the "key" crates, and I only included unstable dependents _where the parent crate was its only pre-1.0 dependency_. The implication is that the "key" parent crate may be the _only_ reason the dependent is still unstable.

This post is not meant to criticize any maintainers. As the above hopefully illustrates, this investigation paints in broad strokes the _potential_ ecosystem that could stabilize as a result of key crates stabilizing. But the degree to which a crate is being "held back" from stability by an unstable parent is more complicated than the simple parent/child relationship.

# Implementation

# More Questions
- Could we identify key by doing this analysis for _all_ crates and determining which are potentially holding back the most _weighty_ group of dependents?
  - As opposed to picking the key crates by how many crates depend on them.
