# frozen_string_literal: true

require "spec_helper"

RSpec.describe Y::UndoManager do
  describe ".new" do
    it "creates an UndoManager scoped to a fragment" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      mgr = Y::UndoManager.new(doc, fragment)
      expect(mgr).to be_a(Y::UndoManager)
    end
  end

  describe "#include_origin" do
    it "tracks changes from the specified origin" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      expect(manager.can_undo?).to be true
    end

    it "does not track changes from untracked origins" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      doc.transact_with("other") do |_tx|
        text << "hello"
      end

      expect(manager.can_undo?).to be false
    end
  end

  describe "#undo" do
    it "undoes the last change" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      expect(text.to_s).to eq("hello")
      manager.undo
      expect(text.to_s).to eq("")
    end

    it "returns true when a change was undone" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      expect(manager.undo).to be true
    end

    it "returns false when nothing to undo" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      expect(manager.undo).to be false
    end
  end

  describe "#redo" do
    it "redoes an undone change" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      manager.undo
      manager.redo
      expect(text.to_s).to eq("hello")
    end

    it "returns false when nothing to redo" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      expect(manager.redo).to be false
    end
  end

  # rubocop:disable RSpec/MultipleExpectations
  describe "#can_undo? and #can_redo?" do
    it "reflects stack state" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      expect(manager.can_undo?).to be false
      expect(manager.can_redo?).to be false

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      expect(manager.can_undo?).to be true

      manager.undo
      expect(manager.can_redo?).to be true
      expect(manager.can_undo?).to be false
    end
  end
  # rubocop:enable RSpec/MultipleExpectations

  describe "#reset" do
    it "forces a stack boundary" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      expect(manager.can_undo?).to be true
      manager.reset
      expect(manager.can_undo?).to be true
    end
  end

  # rubocop:disable RSpec/MultipleExpectations
  describe "#clear" do
    it "empties both stacks" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      doc.transact_with("test") do |_tx|
        text << "hello"
      end

      manager.undo

      manager.clear

      expect(manager.undo_stack_length).to eq(0)
      expect(manager.redo_stack_length).to eq(0)
      expect(manager.can_undo?).to be false
      expect(manager.can_redo?).to be false
    end
  end
  # rubocop:enable RSpec/MultipleExpectations

  # rubocop:disable RSpec/MultipleExpectations
  describe "#undo_stack_length and #redo_stack_length" do
    it "reports stack sizes" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)
      manager.include_origin("test")

      expect(manager.undo_stack_length).to eq(0)
      expect(manager.redo_stack_length).to eq(0)
    end
  end
  # rubocop:enable RSpec/MultipleExpectations

  describe "metadata" do
    it "set_meta accepts Hash arguments" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      expect { manager.set_meta({"description" => "greeting"}) }.not_to raise_error
    end

    it "set_meta accepts Symbol-keyed hashes" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      expect { manager.set_meta(operation: "insert", index: 0) }.not_to raise_error
    end

    it "undo_stack returns array" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      stack = manager.undo_stack
      expect(stack).to be_an(Array)
    end

    it "redo_stack returns array" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      stack = manager.redo_stack
      expect(stack).to be_an(Array)
    end
  end

  describe "#undo_stack and #redo_stack" do
    it "returns arrays" do
      doc = Y::Doc.new
      fragment = doc.get_xml_fragment("content")
      manager = Y::UndoManager.new(doc, fragment)

      undo = manager.undo_stack
      redo_stack = manager.redo_stack

      expect(undo).to be_an(Array)
      expect(redo_stack).to be_an(Array)
    end
  end

  describe "origin scoping" do
    it "skips untracked origins" do
      doc = Y::Doc.new(gc: false)
      text = doc.get_text("content")
      fragment = doc.get_xml_fragment("content")
      mgr = Y::UndoManager.new(doc, fragment)
      mgr.include_origin("ai")

      doc.transact_with("user") do |_tx|
        text << "user "
      end

      doc.transact_with("ai") do |_tx|
        text << "ai"
      end

      mgr.undo
      expect(text.to_s).to eq("user ")
    end
  end
end
