# Snapshot Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Y-CRDT snapshot support to yrb, exposing create/encode/decode/diff-from-snapshot via a new `Y::Snapshot` class and extended `Y::Doc` API.

**Architecture:** New Rust struct `YSnapshot` wrapping `yrs::Snapshot`, registered as `Y::Snapshot` via Magnus. Doc constructor extended with `gc:` keyword. Snapshot creation and state reconstruction methods added to `YDoc`. Ruby wrapper layer provides idiomatic API.

**Tech Stack:** Rust (yrs 0.17.4, magnus 0.8), Ruby (RSpec)

---

### Task 1: Create YSnapshot Rust struct with encode/decode

**Files:**
- Create: `ext/yrb/src/ysnapshot.rs`

**Step 1: Write the Rust module**

```rust
use magnus::{Error, Ruby};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::Snapshot;

#[magnus::wrap(class = "Y::Snapshot")]
pub(crate) struct YSnapshot(pub(crate) Snapshot);

unsafe impl Send for YSnapshot {}

impl YSnapshot {
    pub(crate) fn ysnapshot_encode_v1(&self) -> Vec<u8> {
        self.0.encode_v1()
    }

    pub(crate) fn ysnapshot_encode_v2(&self) -> Vec<u8> {
        self.0.encode_v2()
    }

    pub(crate) fn ysnapshot_decode_v1(encoded: Vec<u8>) -> Result<Self, Error> {
        let ruby = Ruby::get().unwrap();
        Snapshot::decode_v1(encoded.as_slice())
            .map(YSnapshot)
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("cannot decode v1 snapshot: {}", e),
                )
            })
    }

    pub(crate) fn ysnapshot_decode_v2(encoded: Vec<u8>) -> Result<Self, Error> {
        let ruby = Ruby::get().unwrap();
        Snapshot::decode_v2(encoded.as_slice())
            .map(YSnapshot)
            .map_err(|e| {
                Error::new(
                    ruby.exception_runtime_error(),
                    format!("cannot decode v2 snapshot: {}", e),
                )
            })
    }

    pub(crate) fn ysnapshot_equal(&self, other: &YSnapshot) -> bool {
        self.0 == other.0
    }
}

impl From<Snapshot> for YSnapshot {
    fn from(snapshot: Snapshot) -> Self {
        YSnapshot(snapshot)
    }
}
```

**Step 2: Register module in lib.rs**

In `ext/yrb/src/lib.rs`, add `mod ysnapshot;` to the module declarations (after `mod yxml_text;` on line 29), and add `use crate::ysnapshot::YSnapshot;` to the imports (after the `yxml_text` import on line 12).

Then add the class registration block inside `init()`, after the `ydiff` block (after line 676, before `Ok(())`):

```rust
    let ysnapshot = module
        .define_class("Snapshot", ruby.class_object())
        .expect("cannot define class Y::Snapshot");
    ysnapshot
        .define_singleton_method(
            "ysnapshot_decode_v1",
            function!(YSnapshot::ysnapshot_decode_v1, 1),
        )
        .expect("cannot define singleton method: ysnapshot_decode_v1");
    ysnapshot
        .define_singleton_method(
            "ysnapshot_decode_v2",
            function!(YSnapshot::ysnapshot_decode_v2, 1),
        )
        .expect("cannot define singleton method: ysnapshot_decode_v2");
    ysnapshot
        .define_private_method(
            "ysnapshot_encode_v1",
            method!(YSnapshot::ysnapshot_encode_v1, 0),
        )
        .expect("cannot define private method: ysnapshot_encode_v1");
    ysnapshot
        .define_private_method(
            "ysnapshot_encode_v2",
            method!(YSnapshot::ysnapshot_encode_v2, 0),
        )
        .expect("cannot define private method: ysnapshot_encode_v2");
    ysnapshot
        .define_private_method(
            "ysnapshot_equal",
            method!(YSnapshot::ysnapshot_equal, 1),
        )
        .expect("cannot define private method: ysnapshot_equal");
```

**Step 3: Verify it compiles**

Run: `cd /home/fugufish/Code/rails/yrb && cargo build --release`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add ext/yrb/src/ysnapshot.rs ext/yrb/src/lib.rs
git commit -m "feat: add YSnapshot Rust struct with encode/decode/equal"
```

---

### Task 2: Extend YDoc with gc option and snapshot methods

**Files:**
- Modify: `ext/yrb/src/ydoc.rs`

**Step 1: Update imports in ydoc.rs**

Add to the existing imports at the top of the file:

```rust
use crate::ysnapshot::YSnapshot;
use magnus::RHash;
use yrs::updates::encoder::{Encode, EncoderV1, EncoderV2};
```

Note: `Encoder` and `EncoderV2` are already imported. Add `EncoderV1` and `Encode` alongside them. Also add `RHash`.

**Step 2: Update ydoc_new to parse gc: keyword**

Replace the `ydoc_new` method body. The existing method signature uses `&[Value]` (variadic). We need to handle:
- No args: default (gc enabled)
- One integer arg: client_id
- One hash arg: options hash (gc: false)
- Integer + hash: both

```rust
pub(crate) fn ydoc_new(args: &[Value]) -> Self {
    let mut options = Options::default();
    options.offset_kind = OffsetKind::Utf16;

    for arg in args {
        if let Some(int) = Integer::from_value(*arg) {
            options.client_id = int.to_u64().unwrap();
        } else if let Some(hash) = RHash::from_value(*arg) {
            let gc_value: Option<Value> = hash
                .get(magnus::Symbol::new("gc"))
                .unwrap_or(None);
            if let Some(gc) = gc_value {
                // gc: false means skip_gc = true
                let gc_bool = gc.try_convert::<bool>().unwrap_or(true);
                options.skip_gc = !gc_bool;
            }
        }
    }

    let doc = Doc::with_options(options);
    Self(RefCell::new(doc))
}
```

Note: This requires adding `magnus::Symbol` to the import or using it inline. Magnus `RHash::get` returns the value for a given key.

**Step 3: Add snapshot and encode_state_from_snapshot methods**

Add these methods to the `impl YDoc` block:

```rust
pub(crate) fn ydoc_snapshot(&self) -> YSnapshot {
    let doc = self.0.borrow();
    let txn = doc.transact();
    let snapshot = txn.snapshot();
    YSnapshot::from(snapshot)
}

pub(crate) fn ydoc_encode_state_from_snapshot_v1(
    &self,
    snapshot: &YSnapshot,
) -> Result<Vec<u8>, Error> {
    let ruby = Ruby::get().unwrap();
    let doc = self.0.borrow();
    let txn = doc.transact();
    let mut encoder = EncoderV1::new();
    txn.encode_state_from_snapshot(&snapshot.0, &mut encoder)
        .map(|_| encoder.to_vec())
        .map_err(|_e| {
            Error::new(
                ruby.exception_runtime_error(),
                "cannot encode state from snapshot: document was created with \
                 garbage collection enabled. Use Y::Doc.new(gc: false) to \
                 enable snapshot support.",
            )
        })
}

pub(crate) fn ydoc_encode_state_from_snapshot_v2(
    &self,
    snapshot: &YSnapshot,
) -> Result<Vec<u8>, Error> {
    let ruby = Ruby::get().unwrap();
    let doc = self.0.borrow();
    let txn = doc.transact();
    let mut encoder = EncoderV2::new();
    txn.encode_state_from_snapshot(&snapshot.0, &mut encoder)
        .map(|_| encoder.to_vec())
        .map_err(|_e| {
            Error::new(
                ruby.exception_runtime_error(),
                "cannot encode state from snapshot: document was created with \
                 garbage collection enabled. Use Y::Doc.new(gc: false) to \
                 enable snapshot support.",
            )
        })
}
```

**Step 4: Register new methods in lib.rs**

Add to the `ydoc` registration block in `lib.rs` (after the `ydoc_observe_update` registration, around line 125):

```rust
    ydoc.define_private_method("ydoc_snapshot", method!(YDoc::ydoc_snapshot, 0))
        .expect("cannot define private method: ydoc_snapshot");
    ydoc.define_private_method(
        "ydoc_encode_state_from_snapshot_v1",
        method!(YDoc::ydoc_encode_state_from_snapshot_v1, 1),
    )
    .expect("cannot define private method: ydoc_encode_state_from_snapshot_v1");
    ydoc.define_private_method(
        "ydoc_encode_state_from_snapshot_v2",
        method!(YDoc::ydoc_encode_state_from_snapshot_v2, 1),
    )
    .expect("cannot define private method: ydoc_encode_state_from_snapshot_v2");
```

**Step 5: Verify it compiles**

Run: `cd /home/fugufish/Code/rails/yrb && cargo build --release`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add ext/yrb/src/ydoc.rs ext/yrb/src/lib.rs
git commit -m "feat: add gc option to Doc and snapshot/encode_state_from_snapshot methods"
```

---

### Task 3: Create Ruby Y::Snapshot wrapper

**Files:**
- Create: `lib/y/snapshot.rb`
- Modify: `lib/y-rb.rb`

**Step 1: Write the Ruby wrapper**

```ruby
# frozen_string_literal: true

module Y
  class Snapshot
    # Encode snapshot to binary using v1 encoding
    #
    # @return [::Array<Integer>] Binary encoded snapshot
    def encode
      ysnapshot_encode_v1
    end

    # Encode snapshot to binary using v2 encoding
    #
    # @return [::Array<Integer>] Binary encoded snapshot
    def encode_v2
      ysnapshot_encode_v2
    end

    # Decode a snapshot from v1 binary encoding
    #
    # @param bytes [::Array<Integer>] Binary encoded snapshot
    # @return [Y::Snapshot]
    def self.decode(bytes)
      ysnapshot_decode_v1(bytes)
    end

    # Decode a snapshot from v2 binary encoding
    #
    # @param bytes [::Array<Integer>] Binary encoded snapshot
    # @return [Y::Snapshot]
    def self.decode_v2(bytes)
      ysnapshot_decode_v2(bytes)
    end

    # Compare two snapshots for equality
    #
    # @param other [Y::Snapshot]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(Y::Snapshot)

      ysnapshot_equal(other)
    end

    # @!method ysnapshot_encode_v1
    #   Encodes snapshot using v1 encoding
    # @return [::Array<Integer>]
    # @!visibility private

    # @!method ysnapshot_encode_v2
    #   Encodes snapshot using v2 encoding
    # @return [::Array<Integer>]
    # @!visibility private

    # @!method ysnapshot_equal(other)
    #   Compares two snapshots for equality
    # @param other [Y::Snapshot]
    # @return [Boolean]
    # @!visibility private
  end
end
```

**Step 2: Add require to y-rb.rb**

Add `require_relative "y/snapshot"` to `lib/y-rb.rb`, after the `require_relative "y/doc"` line (line 15).

**Step 3: Commit**

```bash
git add lib/y/snapshot.rb lib/y-rb.rb
git commit -m "feat: add Y::Snapshot Ruby wrapper"
```

---

### Task 4: Add snapshot and diff_from_snapshot methods to Y::Doc Ruby wrapper

**Files:**
- Modify: `lib/y/doc.rb`

**Step 1: Add snapshot method**

Add after the `state_v2` method (after line 173):

```ruby
    # Capture a snapshot of the current document state. A snapshot can be
    # used later to reconstruct the document as it was at this point.
    #
    # @return [Y::Snapshot]
    def snapshot
      ydoc_snapshot
    end
```

**Step 2: Add diff_from_snapshot methods**

Add after the new `snapshot` method:

```ruby
    # Encode document state at a past snapshot as a v1 update. Apply the
    # returned bytes to a fresh document to reconstruct the state at that
    # snapshot. Requires the document to have been created with gc: false.
    #
    # @param snapshot [Y::Snapshot]
    # @return [::Array<Integer>] Binary encoded update
    # @raise [RuntimeError] if document has garbage collection enabled
    def diff_from_snapshot(snapshot)
      ydoc_encode_state_from_snapshot_v1(snapshot)
    end

    # Encode document state at a past snapshot as a v2 update. Apply the
    # returned bytes to a fresh document to reconstruct the state at that
    # snapshot. Requires the document to have been created with gc: false.
    #
    # @param snapshot [Y::Snapshot]
    # @return [::Array<Integer>] Binary encoded update
    # @raise [RuntimeError] if document has garbage collection enabled
    def diff_from_snapshot_v2(snapshot)
      ydoc_encode_state_from_snapshot_v2(snapshot)
    end
```

**Step 3: Add YARD docs for the new private methods**

Add at the bottom of the class (before `end`), alongside the other `@!method` docs:

```ruby
    # @!method ydoc_snapshot
    #   Captures a snapshot of the current document state
    #
    # @return [Y::Snapshot]
    # @!visibility private

    # @!method ydoc_encode_state_from_snapshot_v1(snapshot)
    #   Encodes document state from a snapshot using v1 encoding
    #
    # @param snapshot [Y::Snapshot]
    # @return [Array<Integer>]
    # @!visibility private

    # @!method ydoc_encode_state_from_snapshot_v2(snapshot)
    #   Encodes document state from a snapshot using v2 encoding
    #
    # @param snapshot [Y::Snapshot]
    # @return [Array<Integer>]
    # @!visibility private
```

**Step 4: Commit**

```bash
git add lib/y/doc.rb
git commit -m "feat: add snapshot and diff_from_snapshot to Y::Doc"
```

---

### Task 5: Compile extension and write tests

**Files:**
- Create: `spec/y/snapshot_spec.rb`

**Step 1: Compile the extension**

Run: `cd /home/fugufish/Code/rails/yrb && bundle exec rake compile`
Expected: Compiles successfully

**Step 2: Write the snapshot spec**

```ruby
# frozen_string_literal: true

RSpec.describe Y::Snapshot do
  it "creates a snapshot from a document" do
    doc = Y::Doc.new(gc: false)
    doc.get_text("my text")

    snapshot = doc.snapshot

    expect(snapshot).to be_instance_of(described_class)
  end

  it "round-trips encode and decode v1" do
    doc = Y::Doc.new(gc: false)
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot
    encoded = snapshot.encode
    decoded = described_class.decode(encoded)

    expect(decoded).to eq(snapshot)
  end

  it "round-trips encode and decode v2" do
    doc = Y::Doc.new(gc: false)
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot
    encoded = snapshot.encode_v2
    decoded = described_class.decode_v2(encoded)

    expect(decoded).to eq(snapshot)
  end

  it "compares equal snapshots" do
    doc = Y::Doc.new(gc: false)
    snapshot1 = doc.snapshot
    snapshot2 = doc.snapshot

    expect(snapshot1).to eq(snapshot2)
  end

  it "compares different snapshots" do
    doc = Y::Doc.new(gc: false)
    snapshot1 = doc.snapshot

    text = doc.get_text("my text")
    text << "hello"
    snapshot2 = doc.snapshot

    expect(snapshot1).not_to eq(snapshot2)
  end

  # rubocop:disable RSpec/ExampleLength
  it "reconstructs past state with diff_from_snapshot v1" do
    doc = Y::Doc.new(gc: false)
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot

    text << " world"

    update = doc.diff_from_snapshot(snapshot)

    past_doc = Y::Doc.new
    past_doc.sync(update)
    past_text = past_doc.get_text("my text")

    expect(past_text.to_s).to eq("hello")
  end

  it "reconstructs past state with diff_from_snapshot v2" do
    doc = Y::Doc.new(gc: false)
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot

    text << " world"

    update = doc.diff_from_snapshot_v2(snapshot)

    past_doc = Y::Doc.new
    past_doc.sync_v2(update)
    past_text = past_doc.get_text("my text")

    expect(past_text.to_s).to eq("hello")
  end
  # rubocop:enable RSpec/ExampleLength

  it "raises when diff_from_snapshot is called on gc-enabled doc" do
    doc = Y::Doc.new
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot

    text << " world"

    expect { doc.diff_from_snapshot(snapshot) }.to raise_error(RuntimeError, /garbage collection/)
  end

  it "creates a doc with gc: false and client_id" do
    doc = Y::Doc.new(42, gc: false)
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot

    expect(snapshot).to be_instance_of(described_class)
  end

  # rubocop:disable RSpec/ExampleLength
  it "works across multiple edit operations" do
    doc = Y::Doc.new(gc: false)
    text = doc.get_text("my text")

    text << "a"
    snapshot1 = doc.snapshot

    text << "b"
    snapshot2 = doc.snapshot

    text << "c"

    update1 = doc.diff_from_snapshot(snapshot1)
    past1 = Y::Doc.new
    past1.sync(update1)

    update2 = doc.diff_from_snapshot(snapshot2)
    past2 = Y::Doc.new
    past2.sync(update2)

    expect(past1.get_text("my text").to_s).to eq("a")
    expect(past2.get_text("my text").to_s).to eq("ab")
  end
  # rubocop:enable RSpec/ExampleLength
end
```

**Step 3: Run the tests**

Run: `cd /home/fugufish/Code/rails/yrb && bundle exec rspec spec/y/snapshot_spec.rb`
Expected: All tests pass

**Step 4: Run full test suite to check for regressions**

Run: `cd /home/fugufish/Code/rails/yrb && bundle exec rake spec`
Expected: All existing tests still pass

**Step 5: Commit**

```bash
git add spec/y/snapshot_spec.rb
git commit -m "test: add snapshot spec with encode/decode/equality/reconstruction tests"
```

---

### Task 6: Lint and final verification

**Step 1: Run Ruby linting**

Run: `cd /home/fugufish/Code/rails/yrb && bundle exec rubocop lib/y/snapshot.rb lib/y/doc.rb spec/y/snapshot_spec.rb`
Expected: No offenses (fix any that appear)

**Step 2: Run Rust linting**

Run: `cd /home/fugufish/Code/rails/yrb && cargo clippy && cargo fmt --check`
Expected: No warnings or formatting issues (run `cargo fmt` if needed)

**Step 3: Run full test suite one more time**

Run: `cd /home/fugufish/Code/rails/yrb && bundle exec rake`
Expected: All tests pass

**Step 4: Commit any lint fixes**

```bash
git add -A && git commit -m "chore: fix lint offenses"
```
(Only if there were lint fixes needed)
