**Your Position**  
AFFIRM: Rust is the superior choice for systems programming over Go.

**Primary Argument**  
Rust delivers memory safety without garbage collection via its ownership and borrow checker model, enabling predictable latency and tight control of resources that systems code demands. You get C/C++-level performance with compile-time guarantees against data races and most memory bugs, avoiding runtime GC pauses or manual memory pitfalls. That combination—zero-cost abstractions plus strong safety—is uniquely aligned with systems requirements.

**Supporting Points**  
- Concurrency correctness: Rust’s type system encodes Send/Sync and enforces aliasing and mutability rules at compile time, preventing data races before runtime. Go’s CSP model is elegant, but data races are only detected (sometimes) by the race detector and can lurk in production; Rust makes them largely unrepresentable by construction.  
- Compile-time power and optimization: `const fn`, macros, and a rich trait system allow pushing more logic to compile time and generating highly specialized code without runtime overhead. Go’s limited generics and simpler compile-time features constrain zero-cost patterns and specialization.  
- Ecosystem and interoperability: Cargo plus a mature crates.io ecosystem provide first-class support for FFI, `no_std`, embedded targets, and WASM. Systems domains—kernels, drivers, databases, networking stacks—have gravitated to Rust because it fits resource-constrained and safety-critical contexts better than Go’s GC-centric runtime.

**Anticipated Counterarguments**  
- “Go is simpler and faster to build/deploy.” True: Go’s tooling is extremely fast and its language surface is smaller. For some services, that simplicity boosts velocity. But in systems programming, safety/performance guarantees usually outweigh minor build-time gains; Rust’s newer `-Znextest` and incremental compilation continue to improve ergonomics.  
- “Go’s GC is fine for most workloads.” For many server apps, GC pauses are acceptable. In latency-sensitive systems (network stacks, storage engines, embedded), even modest pauses and runtime allocation patterns are liabilities. Rust’s explicit ownership lets you design for bounded latency.  
- “Go’s CSP model makes concurrency easy.” Channels and goroutines are ergonomic, but ease can mask footguns—unbounded goroutine leaks, subtle races on shared state. Rust’s type-checked concurrency requires more upfront design but yields safer, more predictable parallel code.
