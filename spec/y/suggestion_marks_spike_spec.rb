# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Suggestion Marks CRDT Survival" do
  # Test 1: Formatting attributes survive concurrent text insertion within marked range
  describe "Test 1: Formatting attributes survive concurrent text insertion" do
    it "maintains suggestionDelete mark on text after concurrent insertion" do
      # Setup: Doc1 and Doc2 are replicas with "Hello world"
      doc1 = Y::Doc.new
      text1 = doc1.get_text("content")
      text1 << "Hello world"

      doc2 = Y::Doc.new
      text2 = doc2.get_text("content")

      # Sync initial state
      sync1_to_2 = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2)

      # Doc1: apply suggestionDelete formatting to "world" (chars 6-11)
      text1.format(6, 5, {"suggestionDelete" => true})

      # Doc2: insert " beautiful" at position 5
      text2.insert(5, " beautiful")

      # Sync both ways
      sync1_to_2_again = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2_again)

      sync2_to_1 = doc2.diff(doc1.state)
      doc1.sync(sync2_to_1)

      # Verify both have "Hello beautiful world"
      expect(text1.to_s).to eq("Hello beautiful world")
      expect(text2.to_s).to eq("Hello beautiful world")

      # Verify "world" (now at chars 16-21) still has the suggestionDelete attribute
      diff1 = text1.diff
      found_marked = false

      diff1.each do |change|
        if change.insert == "world" && change.attrs&.key?("suggestionDelete")
          found_marked = true
        end
      end

      expect(found_marked).to be(true)
    end
  end

  # Test 2: suggestionAdd mark on inserted text survives concurrent edit
  describe "Test 2: suggestionAdd mark on inserted text survives concurrent edit" do
    it "maintains suggestionAdd attribute after concurrent append" do
      # Setup: Doc1 and Doc2 with "Hello world"
      doc1 = Y::Doc.new
      text1 = doc1.get_text("content")
      text1 << "Hello world"

      doc2 = Y::Doc.new
      text2 = doc2.get_text("content")

      # Sync initial state
      sync1_to_2 = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2)

      # Doc1: insert "beautiful " at position 6 WITH suggestionAdd attribute
      text1.insert(6, "beautiful ", {"suggestionAdd" => true})

      # Doc2: append " today" at position 11 (end of original text)
      text2.insert(11, " today")

      # Sync both ways
      sync1_to_2_again = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2_again)

      sync2_to_1 = doc2.diff(doc1.state)
      doc1.sync(sync2_to_1)

      # Verify both have the expected final text
      expect(text1.to_s).to eq("Hello beautiful world today")
      expect(text2.to_s).to eq("Hello beautiful world today")

      # Verify "beautiful " still has the suggestionAdd attribute
      diff1 = text1.diff
      found_marked = false

      diff1.each do |change|
        if change.insert == "beautiful " && change.attrs&.key?("suggestionAdd")
          found_marked = true
        end
      end

      expect(found_marked).to be(true)
    end
  end

  # Test 3: XMLElement node attributes survive concurrent text edits
  describe "Test 3: XMLElement node attributes survive concurrent text edits" do
    it "maintains suggestionBlock element attribute after concurrent text edit" do
      # Setup: Doc1 and Doc2 with a paragraph containing "Hello"
      doc1 = Y::Doc.new
      fragment1 = doc1.get_xml_fragment("content")
      p1 = fragment1 << "p"
      xml_text1 = p1.push_text("Hello")

      doc2 = Y::Doc.new
      fragment2 = doc2.get_xml_fragment("content")

      # Sync initial state
      sync1_to_2 = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2)

      # Get references in doc2
      p2 = fragment2[0]
      xml_text2 = p2.first_child

      # Doc1: set suggestionBlock attribute on the paragraph element
      p1.set_attribute("suggestionBlock", "true")

      # Doc2: edit the text to "Hello world"
      xml_text2 << " world"

      # Sync both ways
      sync1_to_2_again = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2_again)

      sync2_to_1 = doc2.diff(doc1.state)
      doc1.sync(sync2_to_1)

      # Verify both have the updated text
      expect(p1.first_child.to_s).to eq("Hello world")
      expect(p2.first_child.to_s).to eq("Hello world")

      # Verify both have the suggestionBlock attribute
      expect(p1.get_attribute("suggestionBlock")).to eq("true")
      expect(p2.get_attribute("suggestionBlock")).to eq("true")
    end
  end

  # Test 4: Y::Map stores suggestion metadata and syncs
  describe "Test 4: Y::Map stores suggestion metadata and syncs" do
    it "syncs suggestion metadata in Y.Map across documents" do
      # Setup: Doc1 and Doc2
      doc1 = Y::Doc.new
      suggestions_map1 = doc1.get_map("suggestions")

      doc2 = Y::Doc.new
      suggestions_map2 = doc2.get_map("suggestions")

      # Doc1: insert entry into suggestions map keyed by "batch-1"
      suggestions_map1["batch-1"] = {
        type: "deletion",
        text: "world",
        startChar: 6,
        endChar: 11
      }

      # Sync to Doc2
      sync1_to_2 = doc1.diff(doc2.state)
      doc2.sync(sync1_to_2)

      # Verify Doc2 can read the entry
      batch_entry = suggestions_map2["batch-1"]
      expect(batch_entry).to be_a(Hash)
      expect(batch_entry["type"]).to eq("deletion")
      expect(batch_entry["text"]).to eq("world")
      expect(batch_entry["startChar"]).to eq(6)
      expect(batch_entry["endChar"]).to eq(11)
    end
  end
end
