# frozen_string_literal: true

require "json"
require "digest"
require "base64"

module Y
  module ProseMirror
    MARK_HASH_PATTERN = /\A(.+)(--[a-zA-Z0-9+\/=]{8})\z/

    def self.decode_mark_name(encoded)
      match = encoded.match(MARK_HASH_PATTERN)
      match ? match[1] : encoded
    end

    def self.encode_mark_name(mark_type, attrs)
      return mark_type if attrs.nil? || attrs.empty?

      # Algorithm inspired by y-prosemirror:
      # 1. SHA256 digest of the JSON-encoded attributes
      # 2. XOR-convolute the 32-byte digest down to 6 bytes
      # 3. Base64 encode the 6 bytes to get an 8-char string
      digest = Digest::SHA256.digest(attrs.to_json).bytes
      n = 6
      (n...digest.length).each do |i|
        digest[i % n] = digest[i % n] ^ digest[i]
      end
      hash = Base64.strict_encode64(digest[0, n].pack("C*"))
      "#{mark_type}--#{hash}"
    end
  end
end
