+++
title = "Some Things I Learned This Week"
date = 2025-6-24
+++

# TODO:
- [ ] Make sure links work. I'm not sure if the header link can have an apostrophe ('rust's lexer')

## Sections
- [Disclaimer](#disclaimer)
- [Introduction](#introduction)
- [Rust's Lexer](#rust's-lexer)
- [Debug Asserts](#debug-asserts)
- [Rust's Diagnostics](#rust's-diagnostics)

# Disclaimer
None of this post should be taken as authoritative. I wrote this as an outsider poking around. While I did my best to ensure accuracy, I don't have experience working on the Rust compiler nor do I have much context to add around why certain decisions were made.

# Introduction
I like to understand how things work a little more deeply than necessary to simply use them. One area that has eluded me so far is compilers. Recently I've been working through the CodeCrafters "Crafting Interpreters" challenge. After finishing the lexer, I was curious how this is done in `rustc`

# Rust's Lexer
- [ ] base crate is meant to be as simple as possible. Sends single e.g. 'Eq' tokens to the next stage for "gluing". However, unambiguous groups of text, like // /*, strings, are fully lexed in the rustc_lexer crate.
- [ ] Rust analyzer depends on rustc_lexer, but reimplements the glue stage (needs confirmation)

# Debug Asserts
While poking around the lexer I came across this code:
```rs
/// Returns the last eaten symbol (or `'\0'` in release builds).
/// (For debug assertions only.)
pub(crate) fn prev(&self) -> char {
    #[cfg(debug_assertions)]
    {
        self.prev
    }

    #[cfg(not(debug_assertions))]
    {
        EOF_CHAR
    }
}
```
and immediately wondered why the entire function couldn't be conditionally compiled with `#[cfg(debug_assertions)]`.
Simply speaking, this is because `debug_assert!();` expands to:
```rs
if cfg!(debug_assertions) {
    assert!(...);
}
```
The [official docs](https://doc.rust-lang.org/core/macro.cfg.html) say it best:
> cfg!, unlike #[cfg], does not remove any code and only evaluates to true or false. For example, all blocks in an if/else expression need to be valid when cfg! is used for the condition, regardless of what cfg! is evaluating.
That means that every function used in `debug_assert!()`s, even if they're _only_ used in `debug_assert!()`s, can't be conditionally compiled.
Name resolution, borrow checking, and type checking all run on the code inside the branch.

In release mode, `debug_assert!()` effectively expands to:
```rs
if false {
    assert!(...);
}
```
Once this code gets to the MIR optimizer, all of it should be totally removed, including the bodies of functions that are only referred to in these blocks. So it's actually just as efficient for runtime performance/binary size!

But there's clearly some compile-time cost to compiling all of the code used by `debug_assert!()`. So why doesn't `debug_assert!()` expand to equivalent code that uses `#[cfg(debug_assertions)]` on all of its contents?

That way they wouldn't even be _compiled_ (and we could conditionally compile code only used in `debug_assert!()`s). It seems like the main reason this was done is so that, at the cost of a little compile time, there's never a case where code compiles in one mode (e.g. release) but not another (e.g. debug), leading to bit-rot.

Given that `debug_assert!()` is fairly uncommon and tends not to include too much code, this seems like a sensible design choice.

# Rust's Diagnostics
- [ ] decl_derive sets a custom derive macro (diagnostic_derive)