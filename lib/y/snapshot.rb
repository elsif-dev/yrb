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
