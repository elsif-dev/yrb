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

  it "raises when diff_from_snapshot is called on gc-enabled doc" do
    doc = Y::Doc.new
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot

    text << " world"

    expect do
      doc.diff_from_snapshot(snapshot)
    end.to raise_error(RuntimeError,
                       /garbage collection/)
  end

  it "creates a doc with gc: false and client_id" do
    doc = Y::Doc.new(42, gc: false)
    text = doc.get_text("my text")
    text << "hello"

    snapshot = doc.snapshot

    expect(snapshot).to be_instance_of(described_class)
  end

  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
  it "works across multiple edit operations" do
    doc = Y::Doc.new(gc: false)
    text = doc.get_text("my text")

    # NOTE: yrs 0.17.4 has a block-splitting bug when a client's clock
    # value in the snapshot is exactly 1 (single-character first insert).
    # Using multi-character strings avoids this edge case.
    text << "hello"
    snapshot1 = doc.snapshot

    text << " world"
    snapshot2 = doc.snapshot

    text << " foo"

    update1 = doc.diff_from_snapshot(snapshot1)
    past1 = Y::Doc.new
    past1.sync(update1)

    update2 = doc.diff_from_snapshot(snapshot2)
    past2 = Y::Doc.new
    past2.sync(update2)

    expect(past1.get_text("my text").to_s).to eq("hello")
    expect(past2.get_text("my text").to_s).to eq("hello world")
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
end
