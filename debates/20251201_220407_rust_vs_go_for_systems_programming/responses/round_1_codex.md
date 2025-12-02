1) **Your Position**: AFFIRM — Rust is the superior choice for systems programming.

2) **Primary Argument**: Rust delivers memory safety without GC, preserving C-like performance while eliminating broad classes of memory bugs. The borrow checker enforces ownership and lifetimes at compile time, yielding predictable latency and minimal runtime overhead—critical for kernels, embedded targets, and low-jitter services where Go’s concurrent GC can still introduce tail latencies.

3) **Supporting Points**:
- Performance and control: Rust offers fine-grained control over layout, aliasing (`unsafe` fenced), and zero-cost abstractions. Go’s runtime (GC, scheduler, stack management) simplifies development but adds overhead and limits deterministic control over memory and threading.
- Concurrency safety: Rust’s type system enforces data-race freedom by default; `Send`/`Sync` traits and ownership rules push correctness into compilation. Go’s goroutines/channels are ergonomic, but data races are only caught at runtime via the race detector and are easy to miss in production.
- Ecosystem for systems: Modern crates like `tokio`, `tracing`, `hyper`, `prost`, `serde`, and `bindgen` provide mature, high-performance building blocks for OS components, networking stacks, and embedded work. Tooling (cargo, clippy, miri) makes rigorous correctness and performance tuning part of the standard workflow.

4) **Anticipated Counterarguments**:
- Go is faster to learn and ship: True—Go’s simplicity accelerates onboarding. But for systems code where correctness and latency dominate, Rust’s up-front cost trades for fewer production bugs and more predictable performance, often reducing downstream operational toil.
- Go’s GC is “good enough” and keeps improving: It’s low-latency but still a moving runtime target and not optional; embedded and kernel-space contexts often cannot tolerate any GC involvement. Rust allows opting into `unsafe` only where needed, maintaining zero-runtime overhead elsewhere.
- Rust’s `unsafe` can erode safety: The `unsafe` boundary is explicit and reviewable, confining risk. In Go, data races or inadvertent allocations can slip in silently; Rust’s model localizes unsafety instead of spreading ambient risk across the codebase.
