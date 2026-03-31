# frozen_string_literal: true

require "spec_helper"

RSpec.describe Y::Doc do
  describe "#transact_with" do
    it "creates a transaction with an origin" do
      doc = described_class.new
      text = doc.get_text("test")

      doc.transact_with("my-origin") do |_tx|
        text << "hello"
      end

      expect(text.to_s).to eq("hello")
    end

    it "frees the transaction after the block" do
      doc = described_class.new
      text = doc.get_text("test")

      doc.transact_with("origin1") do |_tx|
        text << "a"
      end

      doc.transact_with("origin2") do |_tx|
        text << "b"
      end

      expect(text.to_s).to eq("ab")
    end

    it "frees on exception" do
      doc = described_class.new
      text = doc.get_text("test")

      expect {
        doc.transact_with("origin") do |_tx|
          raise "boom"
        end
      }.to raise_error(RuntimeError, "boom")

      doc.transact_with("origin") do |_tx|
        text << "after error"
      end

      expect(text.to_s).to eq("after error")
    end
  end
end
