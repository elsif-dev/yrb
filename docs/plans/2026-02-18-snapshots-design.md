# Y-CRDT Snapshot Support

## Summary

Add snapshot support to yrb by exposing the yrs `Snapshot` API. Snapshots capture document state at a point in time, enabling version history, undo/restore, and general-purpose state reconstruction.

## Constraints

- Stay on yrs 0.17.4 (no crate upgrade)
- GC must be disabled on a doc for `diff_from_snapshot` to work
- Follow existing patterns: doc-centric API, implicit transactions, Ruby idioms

## API Design

### Y::Doc Changes

```ruby
# Constructor gains gc: keyword (default true, preserving current behavior)
Y::Doc.new                        # gc enabled
Y::Doc.new(gc: false)             # gc disabled (required for snapshot reconstruction)
Y::Doc.new(client_id)             # existing positional arg preserved
Y::Doc.new(client_id, gc: false)  # both

# New methods
doc.snapshot                       # => Y::Snapshot
doc.diff_from_snapshot(snapshot)   # => Array<Integer> (v1 update bytes)
doc.diff_from_snapshot_v2(snapshot) # => Array<Integer> (v2 update bytes)
```

### Y::Snapshot (new class)

```ruby
snapshot = doc.snapshot

# Encode/decode for persistence
bytes = snapshot.encode          # v1
bytes = snapshot.encode_v2       # v2
snapshot = Y::Snapshot.decode(bytes)
snapshot = Y::Snapshot.decode_v2(bytes)

# Equality
snapshot1 == snapshot2
```

### Typical Usage

```ruby
doc = Y::Doc.new(gc: false)
text = doc.get_text("content")
text << "hello"

snapshot = doc.snapshot

text << " world"

# Reconstruct past state
update = doc.diff_from_snapshot(snapshot)
past_doc = Y::Doc.new
past_doc.sync(update)
# past_doc's text contains "hello" (without " world")
```

## Rust Layer

### New: `ext/yrb/src/ysnapshot.rs`

Wraps `yrs::Snapshot` in a Magnus-compatible struct. Methods:
- `ysnapshot_encode_v1() -> Vec<u8>`
- `ysnapshot_encode_v2() -> Vec<u8>`
- `ysnapshot_decode_v1(bytes) -> YSnapshot` (singleton method)
- `ysnapshot_decode_v2(bytes) -> YSnapshot` (singleton method)
- `ysnapshot_equal(other) -> bool`

### Modified: `ext/yrb/src/ydoc.rs`

- `ydoc_new`: parse `gc:` keyword arg, set `options.skip_gc` accordingly
- `ydoc_snapshot() -> YSnapshot`: create read txn, call `snapshot()`
- `ydoc_encode_state_from_snapshot_v1(snapshot) -> Vec<u8>`
- `ydoc_encode_state_from_snapshot_v2(snapshot) -> Vec<u8>`

### Modified: `ext/yrb/src/lib.rs`

Register `Y::Snapshot` class with singleton and private methods.

## Error Handling

`diff_from_snapshot` on a GC-enabled doc raises `RuntimeError`:
```
Cannot encode state from snapshot: document was created with garbage collection enabled.
Use Y::Doc.new(gc: false) to enable snapshot support.
```

## Testing

Test cases in `spec/y/snapshot_spec.rb`:
1. `doc.snapshot` returns a `Y::Snapshot`
2. Round-trip encode/decode v1 and v2
3. Snapshot equality
4. `diff_from_snapshot` reconstructs past state on a fresh doc
5. `diff_from_snapshot` raises on GC-enabled doc
6. Snapshots across multiple edit operations
7. `Y::Doc.new(gc: false)` works with and without `client_id`
