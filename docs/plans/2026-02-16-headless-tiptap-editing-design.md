# Headless Tiptap Editing via y-rb

**Date:** 2026-02-16
**Status:** Approved
**Scope:** Fix y-rb XML primitives, then build ProseMirror JSON mapping layer

## Problem

AI agents need to edit Tiptap collaborative documents from a Ruby backend without a browser. y-rb has the low-level CRDT primitives but lacks key XML operations and any ProseMirror-aware mapping layer.

## Decision: Fix y-rb primitives + Ruby mapping layer

Evaluated alternatives:
- **Hocuspocus Node.js sidecar** — faster to ship (~3 days) but adds permanent operational complexity and Node.js dependency
- **Automerge** — better CRDT theory but no Ruby bindings exist, ProseMirror binding is beta
- **Loro** — promising future alternative but not production-ready
- **CKEditor 5** — best server-side editing but fails self-hosted requirement (commercial)

y-rb is the best cost/payoff: incremental work on existing infrastructure, zero external dependencies, sub-millisecond edit latency.

## Architecture

```
+-------------------------------------------+
|  Y::ProseMirror (Ruby mapping layer)      |  <- NEW
|  - json_to_fragment / fragment_to_json    |
|  - Mark encoding/decoding                 |
+-------------------------------------------+
|  Y::XMLFragment / XMLElement / XMLText    |  <- FIX gaps
|  (Rust bindings via magnus)               |
+-------------------------------------------+
|  yrs crate (Rust CRDT core)              |  <- EXISTS
+-------------------------------------------+
```

## Target API

```ruby
# Load existing document from storage
doc = Y::Doc.new
doc.sync(binary_state_from_db)

# Read current content as ProseMirror JSON
fragment = doc.get_xml_fragment("default")
json = Y::ProseMirror.fragment_to_json(fragment)

# AI agent makes edits
json["content"] << {
  "type" => "paragraph",
  "content" => [{ "type" => "text", "text" => "AI added this." }]
}

# Write back (incremental update, preserves CRDT history)
doc.transact do
  Y::ProseMirror.update_fragment(fragment, json)
end

# Save binary state back to storage
new_state = doc.full_diff
```

## Phase 1: Rust Binding Gaps

### 1a. XMLFragment text node insertion

The `yrs` crate supports inserting `XmlTextPrelim` into fragments, but the Ruby binding only exposes `XmlElementPrelim`. Add:

**Rust** (`ext/yrb/src/yxml_fragment.rs`):
- `yxml_fragment_push_text_back(tx, content) -> YXmlText`
- `yxml_fragment_push_text_front(tx, content) -> YXmlText`
- `yxml_fragment_insert_text(tx, index, content) -> YXmlText`

**Ruby** (`lib/y/xml.rb`):
- `XMLFragment#push_text(str = "")` — append text child
- `XMLFragment#unshift_text(str = "")` — prepend text child
- `XMLFragment#insert_text(index, str = "")` — insert text child at index

### 1b. XMLText delta/diff reading

`Y::Text` has `diff` returning `Y::Diff` objects. XMLText needs the same to read formatted content with marks.

**Rust** (`ext/yrb/src/yxml_text.rs`):
- `yxml_text_diff(tx) -> RArray` — returns array of `YDiff` (insert + attrs)

**Ruby** (`lib/y/xml.rb`):
- `XMLText#diff` — returns `[Y::Diff]` with `insert` and `attrs` for each formatted chunk

### 1c. Child iteration on XMLElement and XMLFragment

Add `Enumerable` support by implementing `each`:

**Rust**:
- `yxml_element_each(tx, block)` — yields each child node
- `yxml_fragment_each(tx, block)` — yields each child node

**Ruby**:
- `XMLElement` includes `Enumerable`, defines `each`
- `XMLFragment` includes `Enumerable`, defines `each`

### 1d. Make XMLFragment public

Remove `@!visibility private` from `XMLFragment` class. It is the Tiptap document root type and must be a first-class API.

### 1e. Add observe to XMLText

**Rust**: `yxml_text_observe(callback) -> u32`
**Ruby**: `XMLText#attach(callback)` / `XMLText#detach(subscription_id)`

## Phase 2: ProseMirror Mapping Layer

New file: `lib/y/prosemirror.rb`

### 2a. `Y::ProseMirror.fragment_to_json(fragment)` — Read

Walks the XMLFragment tree and converts to ProseMirror JSON hash:

- `XMLElement` with tag name → `{ "type" => tag, "content" => [...], "attrs" => {...} }`
- `XMLText` delta chunks → `{ "type" => "text", "text" => "...", "marks" => [...] }`
- Element attributes → node `attrs` hash (excluding the special `"marks"` key)
- Special `"marks"` attribute on elements → node-level marks array (JSON-decoded)
- Mark name decoding: strips `--base64hash` suffix via regex `/(.*)(--[a-zA-Z0-9+\/=]{8})$/`

### 2b. `Y::ProseMirror.json_to_fragment(fragment, json)` — Write (initial)

Takes ProseMirror JSON and populates an empty XMLFragment:

- Creates `XMLElement` for each block node with `nodeName` = node type
- Creates `XMLText` for inline content with formatted marks
- Sets element attributes from node attrs
- Encodes node-level marks as JSON in the special `"marks"` attribute

### 2c. `Y::ProseMirror.update_fragment(fragment, json)` — Write (update)

Replaces content of an existing XMLFragment while preserving CRDT history:

- Clears existing children
- Rebuilds from JSON within the same transaction
- CRDT history is preserved because changes are incremental operations on an existing doc

### 2d. Mark encoding/decoding

Replicates the y-prosemirror convention:

```ruby
module Y::ProseMirror
  # Non-overlapping marks: bare name ("bold")
  # Overlapping marks: "markName--base64hash" where hash is 8-char base64 of SHA256 of attrs JSON
  def self.encode_mark_name(mark_type, attrs)
    return mark_type if attrs.nil? || attrs.empty?
    hash = Base64.strict_encode64(
      Digest::SHA256.digest(attrs.to_json)
    )[0, 8]
    "#{mark_type}--#{hash}"
  end

  def self.decode_mark_name(encoded)
    match = encoded.match(/\A(.+)(--[a-zA-Z0-9+\/=]{8})\z/)
    match ? match[1] : encoded
  end
end
```

**Important:** The exact hashing algorithm must match y-prosemirror's JavaScript implementation. This needs verification against the y-prosemirror source.

## Testing Strategy

- Unit tests for each new Rust binding method (RSpec in `spec/y/`)
- Integration tests converting known Tiptap document snapshots
- Round-trip test: ProseMirror JSON -> XMLFragment -> ProseMirror JSON = identical output
- Cross-platform test: create Y.Doc in Ruby, verify it renders correctly in a Tiptap editor (manual or scripted)

## Out of Scope

- ProseMirror schema validation (would require porting ProseMirror's schema system)
- Real-time WebSocket sync protocol (direct binary manipulation only)
- Hocuspocus integration
- Incremental diff-based fragment updates (full replacement within transaction first)
- Tiptap extension awareness (custom node types beyond standard ProseMirror)

## Risks

1. **Mark encoding mismatch** — If the hash convention doesn't match y-prosemirror exactly, marks won't round-trip. Mitigation: verify against y-prosemirror source, test with real Tiptap documents.
2. **Tiptap's y-tiptap fork** — Tiptap uses a fork with undocumented differences. Mitigation: test against Tiptap specifically, not just y-prosemirror.
3. **Schema drift** — Server-created content with unknown node types gets silently dropped by clients. Mitigation: document this limitation, recommend testing with target schema.
