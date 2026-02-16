# Headless Tiptap Editing — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable AI agents to read and write Tiptap collaborative documents from Ruby by fixing y-rb XML primitive gaps and building a ProseMirror JSON mapping layer.

**Architecture:** Two-phase approach — Phase 1 fixes missing Rust bindings (text in fragments, XMLText diff, observe), Phase 2 builds a Ruby `Y::ProseMirror` module that converts between ProseMirror JSON and Y-CRDT XML types.

**Tech Stack:** Rust (yrs 0.17.4, magnus), Ruby (RSpec), y-rb gem

**Design doc:** `docs/plans/2026-02-16-headless-tiptap-editing-design.md`

---

## Phase 1: Rust Binding Gaps

### Task 1: XMLFragment — add text node insertion (Rust)

XMLFragment currently only inserts XMLElement children. The `yrs` crate's `XmlFragmentRef` supports `push_back(tx, XmlTextPrelim)` but the binding hardcodes `XmlElementPrelim::empty(tag)`. We need three new Rust methods.

**Files:**
- Modify: `ext/yrb/src/yxml_fragment.rs`
- Modify: `ext/yrb/src/lib.rs` (register new methods)

**Step 1: Add Rust methods to `yxml_fragment.rs`**

Add these three methods to the `impl YXmlFragment` block, after the existing `yxml_fragment_push_front` method (~line 91):

```rust
use yrs::XmlTextPrelim;  // add to existing imports at top of file

pub(crate) fn yxml_fragment_push_text_back(
    &self,
    transaction: &YTransaction,
    content: String,
) -> YXmlText {
    let mut tx = transaction.transaction();
    let tx = tx.as_mut().unwrap();

    let text = XmlTextPrelim::new(content.as_str());
    YXmlText::from(self.0.borrow_mut().push_back(tx, text))
}

pub(crate) fn yxml_fragment_push_text_front(
    &self,
    transaction: &YTransaction,
    content: String,
) -> YXmlText {
    let mut tx = transaction.transaction();
    let tx = tx.as_mut().unwrap();

    let text = XmlTextPrelim::new(content.as_str());
    YXmlText::from(self.0.borrow_mut().push_front(tx, text))
}

pub(crate) fn yxml_fragment_insert_text(
    &self,
    transaction: &YTransaction,
    index: u32,
    content: String,
) -> YXmlText {
    let text = XmlTextPrelim::new(content.as_str());
    let mut tx = transaction.transaction();
    let tx = tx.as_mut().unwrap();

    YXmlText::from(self.0.borrow_mut().insert(tx, index, text))
}
```

Add the `YXmlText` import at the top of the file:
```rust
use crate::yxml_text::YXmlText;  // add if not already present
```

And add `XmlTextPrelim` to the `yrs` import line:
```rust
use yrs::{GetString, XmlElementPrelim, XmlFragment, XmlFragmentRef, XmlNode, XmlTextPrelim};
```

**Step 2: Register new methods in `lib.rs`**

Add after the existing `yxml_fragment_push_front` registration (~line 461):

```rust
yxml_fragment
    .define_private_method(
        "yxml_fragment_push_text_back",
        method!(YXmlFragment::yxml_fragment_push_text_back, 2),
    )
    .expect("cannot define private method: yxml_fragment_push_text_back");
yxml_fragment
    .define_private_method(
        "yxml_fragment_push_text_front",
        method!(YXmlFragment::yxml_fragment_push_text_front, 2),
    )
    .expect("cannot define private method: yxml_fragment_push_text_front");
yxml_fragment
    .define_private_method(
        "yxml_fragment_insert_text",
        method!(YXmlFragment::yxml_fragment_insert_text, 3),
    )
    .expect("cannot define private method: yxml_fragment_insert_text");
```

**Step 3: Verify it compiles**

Run: `cd ext/yrb && cargo build --release 2>&1 | tail -5`
Expected: Compiles without errors.

**Step 4: Commit**

```bash
git add ext/yrb/src/yxml_fragment.rs ext/yrb/src/lib.rs
git commit -m "feat: add text node insertion to XMLFragment (Rust bindings)"
```

---

### Task 2: XMLFragment — Ruby wrappers for text insertion

**Files:**
- Modify: `lib/y/xml.rb` (XMLFragment class)
- Test: `spec/y/xml_fragment_spec.rb`

**Step 1: Write failing tests**

Add to `spec/y/xml_fragment_spec.rb`:

```ruby
it "inserts text at end of children list" do
  doc = Y::Doc.new
  xml_fragment = doc.get_xml_fragment("default")
  text = xml_fragment.push_text("Hello")

  expect(text).to be_a(Y::XMLText)
  expect(text.to_s).to eq("Hello")
  expect(xml_fragment.to_s).to eq("Hello")
end

it "inserts text at front of children list" do
  doc = Y::Doc.new
  xml_fragment = doc.get_xml_fragment("default")
  xml_fragment << "A"
  text = xml_fragment.unshift_text("Front")

  expect(text).to be_a(Y::XMLText)
  expect(xml_fragment.to_s).to start_with("Front")
end

it "inserts text at specific index" do
  doc = Y::Doc.new
  xml_fragment = doc.get_xml_fragment("default")
  xml_fragment << "A"
  xml_fragment << "B"
  text = xml_fragment.insert_text(1, "Middle")

  expect(text).to be_a(Y::XMLText)
  expect(xml_fragment[1]).to be_a(Y::XMLText)
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_fragment_spec.rb -f doc 2>&1 | tail -15`
Expected: 3 new tests FAIL with `NoMethodError`.

**Step 3: Add Ruby wrappers**

Add to the `XMLFragment` class in `lib/y/xml.rb`, after the existing `push`/`<<` method:

```ruby
# Insert new text at the end of this fragment's child list
#
# The optional str argument initializes the text node with its value
#
# @param str [String]
# @return [Y::XMLText]
def push_text(str = "")
  text = document.current_transaction do |tx|
    yxml_fragment_push_text_back(tx, str)
  end
  text.document = document
  text
end

# Insert new text at the front of this fragment's child list
#
# The optional str argument initializes the text node with its value
#
# @param str [String]
# @return [Y::XMLText]
def unshift_text(str = "")
  text = document.current_transaction do |tx|
    yxml_fragment_push_text_front(tx, str)
  end
  text.document = document
  text
end

# Insert text into fragment at given index
#
# Optional input is pushed to the text if provided
#
# @param index [Integer]
# @param input [String]
# @return [Y::XMLText]
def insert_text(index, input = "")
  text = document.current_transaction do |tx|
    yxml_fragment_insert_text(tx, index, input)
  end
  text.document = document
  text
end
```

Also add the YARD method stubs at the bottom of the class (before `end`):

```ruby
# @!method yxml_fragment_push_text_back(tx, text)
#
# @param tx [Y::Transaction]
# @param text [String]
# @return [Y::XMLText]

# @!method yxml_fragment_push_text_front(tx, text)
#
# @param tx [Y::Transaction]
# @param text [String]
# @return [Y::XMLText]

# @!method yxml_fragment_insert_text(tx, index, text)
#
# @param tx [Y::Transaction]
# @param index [Integer]
# @param text [String]
# @return [Y::XMLText]
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_fragment_spec.rb -f doc 2>&1 | tail -15`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/y/xml.rb spec/y/xml_fragment_spec.rb
git commit -m "feat: add text node insertion to XMLFragment (Ruby wrappers)"
```

---

### Task 3: XMLText — add diff/delta reading (Rust)

`Y::Text` has `diff` returning `Y::Diff` objects (insert + attrs). `XMLText` needs the same for reading formatted content. The `yrs` `XmlTextRef` implements the `Text` trait which provides `diff`.

**Files:**
- Modify: `ext/yrb/src/yxml_text.rs`
- Modify: `ext/yrb/src/lib.rs`

**Step 1: Add Rust method to `yxml_text.rs`**

Add the `diff` import and method. Add to the imports at the top:

```rust
use crate::ydiff::YDiff;
use crate::yvalue::YValue;
use magnus::RArray;
use yrs::types::text::YChange;
use yrs::Text;  // for the diff method (XmlTextRef implements Text trait)
```

Note: Some of these imports may already exist. Only add the missing ones. The critical new ones are `YDiff`, `YChange`, and `Text`.

Add the method to the `impl YXmlText` block:

```rust
pub(crate) fn yxml_text_diff(&self, transaction: &YTransaction) -> RArray {
    let ruby = unsafe { Ruby::get_unchecked() };
    let tx = transaction.transaction();
    let tx = tx.as_ref().unwrap();

    let array = ruby.ary_new();
    for diff in self.0.borrow().diff(tx, YChange::identity).iter() {
        let yvalue = YValue::from(diff.insert.clone());
        let insert = yvalue.0.into_inner();
        let attributes = diff.attributes.as_ref().map_or_else(
            || None,
            |boxed_attrs| {
                let attributes = ruby.hash_new();
                for (key, value) in boxed_attrs.iter() {
                    let key = key.to_string();
                    let value = YValue::from(value.clone()).0.into_inner();
                    attributes.aset(key, value).expect("cannot add value");
                }
                Some(attributes)
            },
        );
        let ydiff = YDiff {
            ydiff_insert: insert,
            ydiff_attrs: attributes,
        };
        array
            .push(ydiff.into_value_with(&ruby))
            .expect("cannot push diff to array");
    }
    array
}
```

This is identical to `YText::ytext_diff` — same `Text` trait, same `YChange::identity`, same `YDiff` output.

**Step 2: Register in `lib.rs`**

Add after the existing `yxml_text_attributes` registration:

```rust
yxml_text
    .define_private_method("yxml_text_diff", method!(YXmlText::yxml_text_diff, 1))
    .expect("cannot define private method: yxml_text_diff");
```

**Step 3: Verify it compiles**

Run: `cd ext/yrb && cargo build --release 2>&1 | tail -5`
Expected: Compiles without errors.

**Step 4: Commit**

```bash
git add ext/yrb/src/yxml_text.rs ext/yrb/src/lib.rs
git commit -m "feat: add diff/delta reading to XMLText (Rust bindings)"
```

---

### Task 4: XMLText — Ruby wrapper for diff + tests

**Files:**
- Modify: `lib/y/xml.rb` (XMLText class)
- Test: `spec/y/xml_text_spec.rb`

**Step 1: Write failing tests**

Add to `spec/y/xml_text_spec.rb`:

```ruby
it "returns diff for plain text" do
  doc = Y::Doc.new
  xml_text = doc.get_xml_text("my xml text")
  xml_text << "Hello, World!"

  diff = xml_text.diff

  expect(diff.length).to eq(1)
  expect(diff.first).to be_a(Y::Diff)
  expect(diff.first.insert).to eq("Hello, World!")
end

it "returns diff for formatted text" do
  doc = Y::Doc.new
  xml_text = doc.get_xml_text("my xml text")
  xml_text.insert(0, "Hello ", { "bold" => true })
  xml_text.insert(6, "World!")

  diff = xml_text.diff

  expect(diff.length).to eq(2)
  expect(diff[0].insert).to eq("Hello ")
  expect(diff[0].attrs).to include("bold" => true)
  expect(diff[1].insert).to eq("World!")
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_text_spec.rb -f doc 2>&1 | tail -15`
Expected: 2 new tests FAIL with `NoMethodError: undefined method 'diff'`.

**Step 3: Add Ruby wrapper**

Add to the `XMLText` class in `lib/y/xml.rb`, after the `detach` method:

```ruby
# Returns a list of Diff objects representing formatted chunks of text
#
# @return [Array<Y::Diff>]
def diff
  document.current_transaction { |tx| yxml_text_diff(tx) }
end
```

Add the YARD stub near the other private method stubs:

```ruby
# @!method yxml_text_diff(tx)
#
# @param tx [Y::Transaction]
# @return [Array<Y::Diff>]
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_text_spec.rb -f doc 2>&1 | tail -15`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/y/xml.rb spec/y/xml_text_spec.rb
git commit -m "feat: add diff/delta reading to XMLText (Ruby wrapper)"
```

---

### Task 5: XMLElement + XMLFragment — add Enumerable/each

No new Rust code needed. We can implement `each` purely in Ruby using existing `get(index)` and `size` methods.

**Files:**
- Modify: `lib/y/xml.rb` (both XMLElement and XMLFragment classes)
- Test: `spec/y/xml_element_spec.rb`
- Test: `spec/y/xml_fragment_spec.rb`

**Step 1: Write failing tests**

Add to `spec/y/xml_element_spec.rb`:

```ruby
it "iterates over children with each" do
  doc = Y::Doc.new
  xml_element = doc.get_xml_element("root")
  xml_element << "A"
  xml_element.push_text("hello")
  xml_element << "B"

  children = []
  xml_element.each { |child| children << child }

  expect(children.length).to eq(3)
  expect(children[0]).to be_a(Y::XMLElement)
  expect(children[1]).to be_a(Y::XMLText)
  expect(children[2]).to be_a(Y::XMLElement)
end

it "supports Enumerable methods like map" do
  doc = Y::Doc.new
  xml_element = doc.get_xml_element("root")
  xml_element << "A"
  xml_element << "B"

  tags = xml_element.map(&:tag)

  expect(tags).to eq(%w[A B])
end
```

Add to `spec/y/xml_fragment_spec.rb`:

```ruby
it "iterates over children with each" do
  doc = Y::Doc.new
  xml_fragment = doc.get_xml_fragment("default")
  xml_fragment << "A"
  xml_fragment << "B"
  xml_fragment << "C"

  children = []
  xml_fragment.each { |child| children << child }

  expect(children.length).to eq(3)
  expect(children.map(&:tag)).to eq(%w[A B C])
end

it "supports Enumerable methods like select" do
  doc = Y::Doc.new
  xml_fragment = doc.get_xml_fragment("default")
  xml_fragment << "A"
  xml_fragment << "B"

  result = xml_fragment.select { |child| child.tag == "A" }

  expect(result.length).to eq(1)
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_element_spec.rb spec/y/xml_fragment_spec.rb -f doc 2>&1 | tail -15`
Expected: 4 new tests FAIL.

**Step 3: Add `each` and `Enumerable` to both classes**

In `lib/y/xml.rb`, add to the `XMLElement` class (after `class XMLElement`, before `attr_accessor`):

```ruby
include Enumerable
```

Then add the `each` method (near the other iteration/access methods):

```ruby
# Iterate over direct child nodes
#
# @yield [Y::XMLElement, Y::XMLText, Y::XMLFragment]
# @return [self]
def each(&block)
  return enum_for(:each) unless block_given?

  document.current_transaction do |tx|
    s = yxml_element_size(tx)
    i = 0
    while i < s
      node = yxml_element_get(tx, i)
      node&.document = document
      block.call(node)
      i += 1
    end
  end
  self
end
```

Do the same for `XMLFragment` class. Add `include Enumerable` at the top, then:

```ruby
# Iterate over direct child nodes
#
# @yield [Y::XMLElement, Y::XMLText, Y::XMLFragment]
# @return [self]
def each(&block)
  return enum_for(:each) unless block_given?

  document.current_transaction do |tx|
    s = yxml_fragment_len(tx)
    i = 0
    while i < s
      node = yxml_fragment_get(tx, i)
      node&.document = document
      block.call(node)
      i += 1
    end
  end
  self
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_element_spec.rb spec/y/xml_fragment_spec.rb -f doc 2>&1 | tail -15`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/y/xml.rb spec/y/xml_element_spec.rb spec/y/xml_fragment_spec.rb
git commit -m "feat: add Enumerable/each to XMLElement and XMLFragment"
```

---

### Task 6: Make XMLFragment a public, first-class type

**Files:**
- Modify: `lib/y/xml.rb`

**Step 1: Remove the `@!visibility private` annotation**

In `lib/y/xml.rb`, find the line:
```ruby
  # @!visibility private
  class XMLFragment
```

Change to:
```ruby
  # A XMLFragment
  #
  # Someone should not instantiate a fragment directly, but use
  # {Y::Doc#get_xml_fragment} instead.
  #
  # XMLFragment is the root container type used by Tiptap/ProseMirror
  # for collaborative documents. Use {Y::Doc#get_xml_fragment} with
  # the name "default" to access the Tiptap document root.
  #
  # @example
  #   doc = Y::Doc.new
  #   xml_fragment = doc.get_xml_fragment("default")
  #
  #   puts xml_fragment.to_s
  class XMLFragment
```

**Step 2: Run full test suite**

Run: `bundle exec rake compile && bundle exec rake spec 2>&1 | tail -10`
Expected: All tests PASS. No regressions.

**Step 3: Commit**

```bash
git add lib/y/xml.rb
git commit -m "feat: make XMLFragment a public first-class type"
```

---

### Task 7: XMLText — add observe/unobserve (Rust)

**Files:**
- Modify: `ext/yrb/src/yxml_text.rs`
- Modify: `ext/yrb/src/lib.rs`

**Step 1: Add Rust observe method**

Add to imports at top of `yxml_text.rs`:

```rust
use magnus::block::Proc;
use magnus::value::Qnil;
use yrs::types::Delta;
use yrs::Observable;
```

Add to `impl YXmlText`:

```rust
pub(crate) fn yxml_text_observe(&self, block: Proc) -> Result<u32, Error> {
    let ruby = unsafe { Ruby::get_unchecked() };
    let delta_insert = ruby.to_symbol("insert").to_static();
    let delta_retain = ruby.to_symbol("retain").to_static();
    let delta_delete = ruby.to_symbol("delete").to_static();
    let attributes = ruby.to_symbol("attributes").to_static();

    let subscription_id = self
        .0
        .borrow_mut()
        .observe(move |transaction, text_event| {
            let ruby = unsafe { Ruby::get_unchecked() };
            let delta = text_event.delta(transaction);
            for change in delta.iter() {
                let payload = ruby.hash_new();
                match change {
                    Delta::Inserted(value, attrs) => {
                        let yvalue = YValue::from(value.clone());
                        payload
                            .aset(delta_insert, yvalue.0.into_inner())
                            .expect("cannot set insert");
                        if let Some(a) = attrs {
                            let attrs_hash = ruby.hash_new();
                            for (key, val) in a.iter() {
                                let yvalue = YValue::from(val.clone());
                                attrs_hash
                                    .aset(key.to_string(), yvalue.0.into_inner())
                                    .expect("cannot add attr");
                            }
                            payload.aset(attributes, attrs_hash).expect("cannot set attrs");
                        }
                    }
                    Delta::Retain(index, attrs) => {
                        let yvalue = YValue::from(*index);
                        payload
                            .aset(delta_retain, yvalue.0.into_inner())
                            .expect("cannot set retain");
                        if let Some(a) = attrs {
                            let attrs_hash = ruby.hash_new();
                            for (key, val) in a.iter() {
                                let yvalue = YValue::from(val.clone());
                                attrs_hash
                                    .aset(key.to_string(), yvalue.0.into_inner())
                                    .expect("cannot add attr");
                            }
                            payload.aset(attributes, attrs_hash).expect("cannot set attrs");
                        }
                    }
                    Delta::Deleted(index) => {
                        let yvalue = YValue::from(*index);
                        payload
                            .aset(delta_delete, yvalue.0.into_inner())
                            .expect("cannot set delete");
                    }
                }
                let _ = block.call::<(RHash,), Qnil>((payload,));
            }
        })
        .into();

    Ok(subscription_id)
}

pub(crate) fn yxml_text_unobserve(&self, subscription_id: u32) {
    self.0.borrow_mut().unobserve(subscription_id);
}
```

Note: `RHash` should already be imported. Add `use magnus::RHash;` if not.

**Step 2: Register in `lib.rs`**

Add after existing XMLText methods:

```rust
yxml_text
    .define_private_method("yxml_text_observe", method!(YXmlText::yxml_text_observe, 1))
    .expect("cannot define private method: yxml_text_observe");
yxml_text
    .define_private_method("yxml_text_unobserve", method!(YXmlText::yxml_text_unobserve, 1))
    .expect("cannot define private method: yxml_text_unobserve");
```

**Step 3: Verify it compiles**

Run: `cd ext/yrb && cargo build --release 2>&1 | tail -5`
Expected: Compiles without errors.

**Step 4: Commit**

```bash
git add ext/yrb/src/yxml_text.rs ext/yrb/src/lib.rs
git commit -m "feat: add observe/unobserve to XMLText (Rust bindings)"
```

---

### Task 8: XMLText — Ruby wrappers for observe/unobserve + tests

**Files:**
- Modify: `lib/y/xml.rb` (XMLText class)
- Test: `spec/y/xml_text_spec.rb`

**Step 1: Write failing test**

Add to `spec/y/xml_text_spec.rb`:

```ruby
it "observes changes via attach with block" do
  doc = Y::Doc.new
  xml_text = doc.get_xml_text("my xml text")

  changes = nil
  xml_text.attach { |delta| changes = delta }

  xml_text << "Hello"

  expect(changes).not_to be_nil
  expect(changes[:insert]).to eq("Hello")
end

it "detaches observer" do
  doc = Y::Doc.new
  xml_text = doc.get_xml_text("my xml text")

  count = 0
  sub_id = xml_text.attach { |_delta| count += 1 }

  xml_text << "Hello"
  xml_text.detach(sub_id)
  xml_text << "World"

  expect(count).to eq(1)
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_text_spec.rb -f doc 2>&1 | tail -15`
Expected: Tests FAIL.

**Step 3: Update Ruby wrapper**

The `XMLText` class in `lib/y/xml.rb` already has `attach` and `detach` methods that call `yxml_text_observe` and `yxml_text_unobserve`. These should now work since we registered the Rust methods. If the methods don't exist yet, add:

```ruby
# Attach a listener to get notified about changes
#
# @param callback [Proc]
# @return [Integer] subscription_id
def attach(callback = nil, &block)
  return yxml_text_observe(callback) unless callback.nil?

  yxml_text_observe(block.to_proc) unless block.nil?
end

# Detach a listener
#
# @param subscription_id [Integer]
# @return [void]
def detach(subscription_id)
  yxml_text_unobserve(subscription_id)
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_text_spec.rb -f doc 2>&1 | tail -15`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/y/xml.rb spec/y/xml_text_spec.rb
git commit -m "feat: add observe/unobserve to XMLText (Ruby wrapper)"
```

---

### Task 9: Phase 1 integration test

Verify all Phase 1 primitives work together — build a Tiptap-like document structure from scratch.

**Files:**
- Test: `spec/y/xml_fragment_spec.rb`

**Step 1: Write integration test**

Add to `spec/y/xml_fragment_spec.rb`:

```ruby
context "Tiptap-compatible document structure" do
  it "builds a document with paragraphs and formatted text" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    # Create a paragraph element
    paragraph = fragment << "paragraph"

    # Add text with formatting
    text = paragraph.push_text("")
    text.insert(0, "Hello ", { "bold" => true })
    text.insert(6, "World!")

    # Verify structure
    expect(fragment.size).to eq(1)
    expect(fragment[0]).to be_a(Y::XMLElement)
    expect(fragment[0].tag).to eq("paragraph")

    # Verify text content and formatting
    diff = text.diff
    expect(diff.length).to eq(2)
    expect(diff[0].insert).to eq("Hello ")
    expect(diff[0].attrs).to include("bold" => true)
    expect(diff[1].insert).to eq("World!")
  end

  it "syncs document between two docs" do
    doc1 = Y::Doc.new
    fragment1 = doc1.get_xml_fragment("default")
    para = fragment1 << "paragraph"
    text = para.push_text("Hello from doc1")

    # Sync to doc2
    doc2 = Y::Doc.new
    update = doc1.diff(doc2.state)
    doc2.sync(update)

    fragment2 = doc2.get_xml_fragment("default")
    expect(fragment2.size).to eq(1)
    expect(fragment2[0].tag).to eq("paragraph")
  end

  it "iterates over fragment children" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    fragment << "heading"
    fragment << "paragraph"
    fragment << "paragraph"

    tags = fragment.map(&:tag)
    expect(tags).to eq(%w[heading paragraph paragraph])
  end
end
```

**Step 2: Run the integration tests**

Run: `bundle exec rake compile && bundle exec rspec spec/y/xml_fragment_spec.rb -f doc 2>&1 | tail -20`
Expected: All tests PASS.

**Step 3: Run full test suite to check for regressions**

Run: `bundle exec rake 2>&1 | tail -10`
Expected: All tests PASS.

**Step 4: Commit**

```bash
git add spec/y/xml_fragment_spec.rb
git commit -m "test: add Phase 1 integration tests for Tiptap-compatible structures"
```

---

## Phase 2: ProseMirror Mapping Layer

### Task 10: Mark encoding/decoding module

The y-prosemirror library encodes overlapping marks (those with attributes like `link`) using a `markName--base64hash` convention. Non-overlapping marks (like `bold`) use bare names.

**Important:** Before implementing, verify the exact hashing algorithm against the y-prosemirror source. The design doc assumes SHA256 + base64, but the actual implementation may differ.

**Files:**
- Create: `lib/y/prosemirror.rb`
- Test: `spec/y/prosemirror_spec.rb`

**Step 1: Research the actual y-prosemirror hash algorithm**

Check the y-prosemirror source at `https://github.com/yjs/y-prosemirror/blob/master/src/plugins/sync-plugin.js` for the exact implementation of mark name encoding. Look for a function that converts mark attributes to a hash suffix. The key function names to look for are `markName`, `typeHash`, or similar.

**Step 2: Write failing tests**

Create `spec/y/prosemirror_spec.rb`:

```ruby
# frozen_string_literal: true

require "json"

RSpec.describe Y::ProseMirror do
  describe ".decode_mark_name" do
    it "returns bare mark name for non-overlapping marks" do
      expect(Y::ProseMirror.decode_mark_name("bold")).to eq("bold")
    end

    it "strips hash suffix for overlapping marks" do
      # 8 char base64 suffix
      expect(Y::ProseMirror.decode_mark_name("link--ABCD1234")).to eq("link")
    end

    it "handles mark names with hyphens" do
      expect(Y::ProseMirror.decode_mark_name("text-style--ABCD1234")).to eq("text-style")
    end

    it "does not strip suffixes that are not valid base64" do
      expect(Y::ProseMirror.decode_mark_name("my-mark--short")).to eq("my-mark--short")
    end
  end

  describe ".encode_mark_name" do
    it "returns bare name for marks without attributes" do
      expect(Y::ProseMirror.encode_mark_name("bold", nil)).to eq("bold")
      expect(Y::ProseMirror.encode_mark_name("bold", {})).to eq("bold")
    end

    it "appends hash for marks with attributes" do
      encoded = Y::ProseMirror.encode_mark_name("link", { "href" => "https://example.com" })
      expect(encoded).to match(/\Alink--[a-zA-Z0-9+\/=]{8}\z/)
    end

    it "produces consistent hashes for same attributes" do
      attrs = { "href" => "https://example.com" }
      a = Y::ProseMirror.encode_mark_name("link", attrs)
      b = Y::ProseMirror.encode_mark_name("link", attrs)
      expect(a).to eq(b)
    end

    it "produces different hashes for different attributes" do
      a = Y::ProseMirror.encode_mark_name("link", { "href" => "https://a.com" })
      b = Y::ProseMirror.encode_mark_name("link", { "href" => "https://b.com" })
      expect(a).not_to eq(b)
    end
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -15`
Expected: FAIL with `uninitialized constant Y::ProseMirror`.

**Step 4: Implement mark encoding/decoding**

Create `lib/y/prosemirror.rb`:

```ruby
# frozen_string_literal: true

require "json"
require "digest"
require "base64"

module Y
  # ProseMirror JSON conversion utilities for Y-CRDT XML types.
  #
  # This module provides conversion between ProseMirror/Tiptap JSON format
  # and Y-CRDT XML types (XMLFragment, XMLElement, XMLText), enabling
  # headless editing of Tiptap collaborative documents from Ruby.
  module ProseMirror
    # Regex to match the y-prosemirror mark name encoding convention.
    # Overlapping marks are encoded as "markName--base64hash" where the
    # hash is an 8-character base64 string derived from the mark attributes.
    MARK_HASH_PATTERN = /\A(.+)(--[a-zA-Z0-9+\/=]{8})\z/

    # Decode a mark name from y-prosemirror format.
    #
    # Non-overlapping marks use bare names ("bold").
    # Overlapping marks use "markName--base64hash" format.
    #
    # @param encoded [String] the encoded mark name
    # @return [String] the decoded mark type name
    def self.decode_mark_name(encoded)
      match = encoded.match(MARK_HASH_PATTERN)
      match ? match[1] : encoded
    end

    # Encode a mark name in y-prosemirror format.
    #
    # Non-overlapping marks (no attributes) use bare names.
    # Overlapping marks (with attributes) use "markName--base64hash".
    #
    # @param mark_type [String] the mark type name
    # @param attrs [Hash, nil] the mark attributes
    # @return [String] the encoded mark name
    def self.encode_mark_name(mark_type, attrs)
      return mark_type if attrs.nil? || attrs.empty?

      hash = Base64.strict_encode64(
        Digest::SHA256.digest(attrs.to_json)
      )[0, 8]
      "#{mark_type}--#{hash}"
    end
  end
end
```

Add the require to the entry point. In `lib/y-rb.rb` (or wherever the gem requires its files), add:

```ruby
require_relative "y/prosemirror"
```

**Step 5: Run tests to verify they pass**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -15`
Expected: All tests PASS.

**Step 6: Commit**

```bash
git add lib/y/prosemirror.rb spec/y/prosemirror_spec.rb lib/y-rb.rb
git commit -m "feat: add ProseMirror mark encoding/decoding"
```

---

### Task 11: `fragment_to_json` — Read Y.Doc as ProseMirror JSON

**Files:**
- Modify: `lib/y/prosemirror.rb`
- Modify: `spec/y/prosemirror_spec.rb`

**Step 1: Write failing tests**

Add to `spec/y/prosemirror_spec.rb`:

```ruby
describe ".fragment_to_json" do
  it "converts empty fragment to doc JSON" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    json = Y::ProseMirror.fragment_to_json(fragment)

    expect(json).to eq({ "type" => "doc", "content" => [] })
  end

  it "converts fragment with paragraph and plain text" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    para = fragment << "paragraph"
    para.push_text("Hello, World!")

    json = Y::ProseMirror.fragment_to_json(fragment)

    expect(json).to eq({
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "Hello, World!" }
          ]
        }
      ]
    })
  end

  it "converts fragment with formatted text (bold)" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    para = fragment << "paragraph"
    text = para.push_text("")
    text.insert(0, "bold text", { "bold" => true })

    json = Y::ProseMirror.fragment_to_json(fragment)
    text_node = json.dig("content", 0, "content", 0)

    expect(text_node["type"]).to eq("text")
    expect(text_node["text"]).to eq("bold text")
    expect(text_node["marks"]).to include({ "type" => "bold", "attrs" => true })
  end

  it "converts fragment with element attributes" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    heading = fragment << "heading"
    heading.attr_level = "2"
    heading.push_text("Title")

    json = Y::ProseMirror.fragment_to_json(fragment)
    heading_node = json["content"].first

    expect(heading_node["type"]).to eq("heading")
    expect(heading_node["attrs"]).to eq({ "level" => "2" })
  end

  it "converts nested elements" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    blockquote = fragment << "blockquote"
    para = blockquote << "paragraph"
    para.push_text("Quoted text")

    json = Y::ProseMirror.fragment_to_json(fragment)

    expect(json["content"].first["type"]).to eq("blockquote")
    expect(json.dig("content", 0, "content", 0, "type")).to eq("paragraph")
    expect(json.dig("content", 0, "content", 0, "content", 0, "text")).to eq("Quoted text")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -15`
Expected: FAIL with `NoMethodError: undefined method 'fragment_to_json'`.

**Step 3: Implement `fragment_to_json`**

Add to `lib/y/prosemirror.rb` inside the `ProseMirror` module:

```ruby
# Convert a Y::XMLFragment to ProseMirror JSON format.
#
# @param fragment [Y::XMLFragment] the fragment to convert
# @return [Hash] ProseMirror-compatible JSON hash
def self.fragment_to_json(fragment)
  {
    "type" => "doc",
    "content" => children_to_json(fragment)
  }
end

# @!visibility private
def self.children_to_json(parent)
  result = []
  parent.each do |child|
    case child
    when Y::XMLElement
      result << element_to_json(child)
    when Y::XMLText
      result.concat(xml_text_to_json(child))
    end
  end
  result
end

# @!visibility private
def self.element_to_json(element)
  node = { "type" => element.tag }

  # Extract attributes (excluding special "marks" key)
  attrs = element.attrs
  marks_json = attrs.delete("marks")
  node["attrs"] = attrs unless attrs.empty?

  # Node-level marks
  if marks_json
    node["marks"] = JSON.parse(marks_json)
  end

  # Recurse into children
  content = children_to_json(element)
  node["content"] = content unless content.empty?

  node
end

# @!visibility private
def self.xml_text_to_json(xml_text)
  xml_text.diff.map do |chunk|
    text_node = { "type" => "text", "text" => chunk.insert.to_s }

    if chunk.attrs && !chunk.attrs.empty?
      marks = chunk.attrs.map do |encoded_name, value|
        mark_type = decode_mark_name(encoded_name)
        { "type" => mark_type, "attrs" => value }
      end
      text_node["marks"] = marks
    end

    text_node
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -15`
Expected: All tests PASS. If any fail, debug the specific conversion and adjust.

**Step 5: Commit**

```bash
git add lib/y/prosemirror.rb spec/y/prosemirror_spec.rb
git commit -m "feat: add fragment_to_json for reading Y.Doc as ProseMirror JSON"
```

---

### Task 12: `json_to_fragment` — Write ProseMirror JSON to Y.Doc

**Files:**
- Modify: `lib/y/prosemirror.rb`
- Modify: `spec/y/prosemirror_spec.rb`

**Step 1: Write failing tests**

Add to `spec/y/prosemirror_spec.rb`:

```ruby
describe ".json_to_fragment" do
  it "populates fragment from simple paragraph JSON" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "Hello, World!" }
          ]
        }
      ]
    }

    Y::ProseMirror.json_to_fragment(fragment, json)

    expect(fragment.size).to eq(1)
    expect(fragment[0].tag).to eq("paragraph")
    expect(fragment[0][0].to_s).to eq("Hello, World!")
  end

  it "populates fragment with formatted text" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "bold", "marks" => [{ "type" => "bold" }] },
            { "type" => "text", "text" => " normal" }
          ]
        }
      ]
    }

    Y::ProseMirror.json_to_fragment(fragment, json)

    text_node = fragment[0][0]
    diff = text_node.diff
    expect(diff[0].insert).to eq("bold")
    expect(diff[0].attrs).to have_key("bold")
    expect(diff[1].insert).to eq(" normal")
  end

  it "populates fragment with element attributes" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "heading",
          "attrs" => { "level" => "2" },
          "content" => [
            { "type" => "text", "text" => "Title" }
          ]
        }
      ]
    }

    Y::ProseMirror.json_to_fragment(fragment, json)

    heading = fragment[0]
    expect(heading.tag).to eq("heading")
    expect(heading.attrs).to include("level" => "2")
  end

  it "populates nested elements" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "blockquote",
          "content" => [
            {
              "type" => "paragraph",
              "content" => [
                { "type" => "text", "text" => "Quoted" }
              ]
            }
          ]
        }
      ]
    }

    Y::ProseMirror.json_to_fragment(fragment, json)

    expect(fragment[0].tag).to eq("blockquote")
    expect(fragment[0][0].tag).to eq("paragraph")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -15`
Expected: FAIL with `NoMethodError: undefined method 'json_to_fragment'`.

**Step 3: Implement `json_to_fragment`**

Add to `lib/y/prosemirror.rb` inside the `ProseMirror` module:

```ruby
# Populate a Y::XMLFragment from ProseMirror JSON.
#
# This should only be used for initial document creation.
# For updating existing documents, use {.update_fragment}.
#
# @param fragment [Y::XMLFragment] the fragment to populate (should be empty)
# @param json [Hash] ProseMirror-compatible JSON hash with "type" and "content"
# @return [void]
def self.json_to_fragment(fragment, json)
  return unless json["content"]

  json["content"].each do |node_json|
    write_node(fragment, node_json)
  end
end

# @!visibility private
def self.write_node(parent, node_json)
  if node_json["type"] == "text"
    write_text_node(parent, node_json)
  else
    write_element_node(parent, node_json)
  end
end

# @!visibility private
def self.write_element_node(parent, node_json)
  element = parent << node_json["type"]

  # Set attributes
  if node_json["attrs"]
    node_json["attrs"].each do |key, value|
      element.document.current_transaction do |tx|
        element.send(:yxml_element_insert_attribute, tx, key, value.to_s)
      end
    end
  end

  # Set node-level marks
  if node_json["marks"]
    element.document.current_transaction do |tx|
      element.send(:yxml_element_insert_attribute, tx, "marks", node_json["marks"].to_json)
    end
  end

  # Recurse into children
  if node_json["content"]
    node_json["content"].each do |child_json|
      write_node(element, child_json)
    end
  end
end

# @!visibility private
def self.write_text_node(parent, node_json)
  text_content = node_json["text"] || ""
  marks = node_json["marks"] || []

  text = parent.push_text("")

  if marks.empty?
    text.insert(0, text_content)
  else
    # Build attrs hash from marks
    attrs = {}
    marks.each do |mark|
      mark_attrs = mark["attrs"]
      encoded_name = encode_mark_name(mark["type"], mark_attrs)
      attrs[encoded_name] = mark_attrs || {}
    end
    text.insert(0, text_content, attrs)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/y/prosemirror.rb spec/y/prosemirror_spec.rb
git commit -m "feat: add json_to_fragment for writing ProseMirror JSON to Y.Doc"
```

---

### Task 13: `update_fragment` — Update existing fragment

**Files:**
- Modify: `lib/y/prosemirror.rb`
- Modify: `spec/y/prosemirror_spec.rb`

**Step 1: Write failing tests**

Add to `spec/y/prosemirror_spec.rb`:

```ruby
describe ".update_fragment" do
  it "replaces existing content" do
    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")

    # Initial content
    initial_json = {
      "type" => "doc",
      "content" => [
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Old" }] }
      ]
    }
    Y::ProseMirror.json_to_fragment(fragment, initial_json)
    expect(fragment[0][0].to_s).to eq("Old")

    # Update
    new_json = {
      "type" => "doc",
      "content" => [
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "New" }] }
      ]
    }
    Y::ProseMirror.update_fragment(fragment, new_json)

    expect(fragment.size).to eq(1)
    expect(fragment[0][0].to_s).to eq("New")
  end

  it "preserves CRDT history (syncable)" do
    doc1 = Y::Doc.new
    fragment1 = doc1.get_xml_fragment("default")

    initial = {
      "type" => "doc",
      "content" => [
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Hello" }] }
      ]
    }
    Y::ProseMirror.json_to_fragment(fragment1, initial)

    # Sync to doc2
    doc2 = Y::Doc.new
    doc2.sync(doc1.diff(doc2.state))

    # Update doc1
    updated = {
      "type" => "doc",
      "content" => [
        { "type" => "paragraph", "content" => [{ "type" => "text", "text" => "Updated" }] }
      ]
    }

    state_before = doc2.state
    Y::ProseMirror.update_fragment(fragment1, updated)

    # Sync the update
    update_diff = doc1.diff(state_before)
    doc2.sync(update_diff)

    fragment2 = doc2.get_xml_fragment("default")
    expect(fragment2[0][0].to_s).to eq("Updated")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -15`
Expected: FAIL with `NoMethodError: undefined method 'update_fragment'`.

**Step 3: Implement `update_fragment`**

Add to `lib/y/prosemirror.rb`:

```ruby
# Update an existing Y::XMLFragment with new ProseMirror JSON.
#
# Clears existing content and rebuilds from JSON within a transaction.
# CRDT history is preserved because operations are incremental.
#
# @param fragment [Y::XMLFragment] the fragment to update
# @param json [Hash] ProseMirror-compatible JSON hash
# @return [void]
def self.update_fragment(fragment, json)
  fragment.document.transact do
    # Clear existing children
    current_size = fragment.size
    fragment.slice!(0, current_size) if current_size > 0

    # Rebuild from JSON
    json_to_fragment(fragment, json)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -20`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/y/prosemirror.rb spec/y/prosemirror_spec.rb
git commit -m "feat: add update_fragment for updating existing documents"
```

---

### Task 14: Round-trip tests

Verify JSON -> XMLFragment -> JSON produces identical output.

**Files:**
- Modify: `spec/y/prosemirror_spec.rb`

**Step 1: Write round-trip tests**

Add to `spec/y/prosemirror_spec.rb`:

```ruby
describe "round-trip conversion" do
  it "round-trips simple paragraph" do
    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => "Hello, World!" }
          ]
        }
      ]
    }

    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    Y::ProseMirror.json_to_fragment(fragment, json)
    result = Y::ProseMirror.fragment_to_json(fragment)

    expect(result).to eq(json)
  end

  it "round-trips heading with attributes" do
    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "heading",
          "attrs" => { "level" => "2" },
          "content" => [
            { "type" => "text", "text" => "My Heading" }
          ]
        }
      ]
    }

    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    Y::ProseMirror.json_to_fragment(fragment, json)
    result = Y::ProseMirror.fragment_to_json(fragment)

    expect(result).to eq(json)
  end

  it "round-trips multiple paragraphs" do
    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [{ "type" => "text", "text" => "First" }]
        },
        {
          "type" => "paragraph",
          "content" => [{ "type" => "text", "text" => "Second" }]
        }
      ]
    }

    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    Y::ProseMirror.json_to_fragment(fragment, json)
    result = Y::ProseMirror.fragment_to_json(fragment)

    expect(result).to eq(json)
  end

  it "round-trips nested blockquote" do
    json = {
      "type" => "doc",
      "content" => [
        {
          "type" => "blockquote",
          "content" => [
            {
              "type" => "paragraph",
              "content" => [{ "type" => "text", "text" => "Quoted" }]
            }
          ]
        }
      ]
    }

    doc = Y::Doc.new
    fragment = doc.get_xml_fragment("default")
    Y::ProseMirror.json_to_fragment(fragment, json)
    result = Y::ProseMirror.fragment_to_json(fragment)

    expect(result).to eq(json)
  end
end
```

**Step 2: Run round-trip tests**

Run: `bundle exec rspec spec/y/prosemirror_spec.rb -f doc 2>&1 | tail -20`
Expected: All tests PASS. If any fail, the mismatch indicates a bug in either `json_to_fragment` or `fragment_to_json` — debug by comparing the intermediate XMLFragment structure.

**Step 3: Commit**

```bash
git add spec/y/prosemirror_spec.rb
git commit -m "test: add round-trip conversion tests for ProseMirror JSON"
```

---

### Task 15: Full regression test + final commit

**Files:** None new — just running the full suite.

**Step 1: Run the complete test suite**

Run: `bundle exec rake 2>&1 | tail -15`
Expected: All tests PASS, including the original tests and all new tests.

**Step 2: Run linting**

Run: `bundle exec rubocop lib/y/prosemirror.rb lib/y/xml.rb 2>&1 | tail -10`
Expected: No offenses. If there are offenses, fix them.

Run: `cd ext/yrb && cargo clippy 2>&1 | tail -10`
Expected: No warnings. If there are warnings, fix them.

Run: `cd ext/yrb && cargo fmt --check 2>&1`
Expected: No formatting issues.

**Step 3: Fix any issues, commit**

If linting found issues:
```bash
bundle exec rubocop -A lib/y/prosemirror.rb lib/y/xml.rb
cd ext/yrb && cargo fmt
git add -A
git commit -m "chore: fix linting issues"
```

**Step 4: Final summary commit**

If all is clean and no extra commit was needed, the implementation is complete.
