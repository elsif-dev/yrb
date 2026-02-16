# frozen_string_literal: true

require "json"

RSpec.describe Y::ProseMirror do
  describe ".decode_mark_name" do
    it "returns bare mark name for non-overlapping marks" do
      expect(described_class.decode_mark_name("bold")).to eq("bold")
    end

    it "strips hash suffix for overlapping marks" do
      expect(described_class.decode_mark_name("link--ABCD1234")).to eq("link")
    end

    it "handles mark names with hyphens" do
      expect(described_class.decode_mark_name("text-style--ABCD1234")).to eq("text-style")
    end

    it "does not strip suffixes that are not valid 8-char base64" do
      expect(described_class.decode_mark_name("my-mark--short")).to eq("my-mark--short")
    end
  end

  describe ".encode_mark_name" do
    it "returns bare name for marks without attributes" do
      expect(described_class.encode_mark_name("bold", nil)).to eq("bold")
      expect(described_class.encode_mark_name("bold", {})).to eq("bold")
    end

    it "appends hash for marks with attributes" do
      encoded = described_class.encode_mark_name("link", { "href" => "https://example.com" })
      expect(encoded).to match(/\Alink--[a-zA-Z0-9+\/=]{8}\z/)
    end

    it "produces consistent hashes for same attributes" do
      attrs = { "href" => "https://example.com" }
      a = described_class.encode_mark_name("link", attrs)
      b = described_class.encode_mark_name("link", attrs)
      expect(a).to eq(b)
    end

    it "produces different hashes for different attributes" do
      a = described_class.encode_mark_name("link", { "href" => "https://a.com" })
      b = described_class.encode_mark_name("link", { "href" => "https://b.com" })
      expect(a).not_to eq(b)
    end
  end
end
