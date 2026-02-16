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

    def self.fragment_to_json(fragment)
      {
        "type" => "doc",
        "content" => children_to_json(fragment)
      }
    end

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
    private_class_method :children_to_json

    def self.element_to_json(element)
      node = { "type" => element.tag }

      attrs = element.attrs.dup
      marks_json = attrs.delete("marks")
      node["attrs"] = attrs unless attrs.empty?
      node["marks"] = JSON.parse(marks_json) if marks_json

      content = children_to_json(element)
      node["content"] = content unless content.empty?

      node
    end
    private_class_method :element_to_json

    def self.xml_text_to_json(xml_text)
      xml_text.diff.map do |chunk|
        text_node = { "type" => "text", "text" => chunk.insert.to_s }
        if chunk.attrs && !chunk.attrs.empty?
          marks = chunk.attrs.map do |encoded_name, value|
            mark = { "type" => decode_mark_name(encoded_name) }
            mark["attrs"] = value unless value.nil? || (value.is_a?(Hash) && value.empty?)
            mark
          end
          text_node["marks"] = marks
        end
        text_node
      end
    end
    private_class_method :xml_text_to_json
  end
end
