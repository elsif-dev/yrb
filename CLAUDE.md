# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

yrb (y-rb) is a Ruby gem providing bindings for Y-CRDT (Yrs), enabling real-time collaborative data structures. It's a hybrid Ruby/Rust project where Rust handles the performance-critical CRDT operations and Ruby provides an idiomatic interface.

## Development Commands

### Building
```bash
# Build the Rust extension
cargo build --release

# Compile the extension for development
bundle exec rake compile

# Setup after checkout
bin/setup
```

### Testing
```bash
# Run all tests (default rake task)
bundle exec rake
# or
bundle exec rake spec

# Run specific test file
bundle exec rspec spec/y/doc_spec.rb

# Run benchmarks
bundle exec rake bench
```

### Linting
```bash
# Ruby linting
bundle exec rake rubocop
# or
bundle exec rubocop

# Rust linting
cargo clippy
cargo fmt --check

# Fix Rust formatting
cargo fmt
```

### Documentation
```bash
# Start YARD documentation server
yard server
# Visit http://0.0.0.0:8808/

# Generate docs
bundle exec rake yard
```

### Cross-Platform Compilation
```bash
# Build for specific platform
bundle exec rake gem:<platform>

# Supported platforms:
# - aarch64-linux-gnu
# - aarch64-linux-musl
# - arm64-darwin
# - x86_64-darwin
# - x86_64-linux-gnu
# - x86_64-linux-musl
# - x64-mingw32
# - x64-mingw-ucrt
```

## Architecture

### Ruby-Rust Hybrid Structure

The codebase follows a two-layer architecture:

1. **Rust Extension Layer** (`ext/yrb/src/`)
   - Core CRDT implementations wrapping the `yrs` crate
   - Each Y-CRDT type has its own module: `ydoc.rs`, `yarray.rs`, `ymap.rs`, `ytext.rs`, `yxml_element.rs`, `yxml_fragment.rs`, `yxml_text.rs`
   - `yawareness.rs` handles distributed state awareness
   - `ytransaction.rs` manages transactional updates
   - Uses `magnus` for Ruby-Rust FFI
   - Methods are exposed as private Ruby methods (prefixed with type name, e.g., `yarray_push_back`)

2. **Ruby Wrapper Layer** (`lib/y/`)
   - Provides idiomatic Ruby interfaces wrapping Rust methods
   - Each file corresponds to a Y-CRDT type: `doc.rb`, `array.rb`, `map.rb`, `text.rb`, `xml.rb`
   - `awareness.rb` wraps distributed awareness functionality
   - `transaction.rb` exposes transaction control when needed
   - Entry point is `lib/y-rb.rb` (loaded via `lib/y.rb`)

### Key Design Decisions

**Implicit Transactions by Default**
- Most operations automatically create transactions
- Developers should not be exposed to transactions unless they need explicit control
- Multiple operations on the same structure are part of the same transaction by default
- See `docs/decisions.md` for the rationale

**No Direct Y-CRDT API Exposure**
- The Ruby API does not mirror the internal `yrs` API exactly
- Prefers Ruby idioms over direct Rust API translation
- This allows the Ruby interface to remain stable even as the Rust implementation changes

**Synchronization at Document Level**
- All sync operations happen at the `Y::Doc` level, not at individual structure level
- Use `doc.diff(remote_state)` to create updates and `doc.sync(update)` to apply them

**Read-Only vs Mutable Operations**
- Avoid creating new instances of data types repeatedly
- This contradicts CRDT replication patterns and causes problems
- The API makes it explicit whether operations are read-only or mutating

### Type System

All Y-CRDT types inherit from Ruby's `Object` and are defined in the `Y` module:
- `Y::Doc` - Root document container
- `Y::Array` - Collaborative array
- `Y::Map` - Collaborative map
- `Y::Text` - Collaborative text
- `Y::XMLElement`, `Y::XMLFragment`, `Y::XMLText` - Collaborative XML structures
- `Y::Transaction` - Explicit transaction control
- `Y::Awareness` - Distributed state awareness

## Working with the Codebase

### Adding New Y-CRDT Methods

When adding new functionality:

1. Implement the method in the appropriate Rust module (`ext/yrb/src/y*.rs`)
2. Register it in `ext/yrb/src/lib.rs` using `define_private_method` or `define_method`
3. Add the Ruby wrapper in the corresponding `lib/y/*.rb` file
4. Write RSpec tests in `spec/y/*_spec.rb`

### Testing Strategy

- Tests use RSpec (`spec/` directory)
- Each Y-CRDT type has its own spec file
- Benchmark tests are tagged with `:bench` and run separately
- Bug regression tests are in `spec/y/bugs_spec.rb`

### Ruby Version Requirements

- Minimum Ruby version: 3.1.0
- Minimum RubyGems version: 3.3.22 (for musl platform support)
- CI tests against Ruby 3.1, 3.2, 3.3, 3.4, and 4.0

### Platform Notes

The gem ships with pre-compiled binaries for multiple platforms. On `x86_64-linux-musl` systems, older RubyGems versions (<3.3.22) have a bug that prevents correct platform detection.
