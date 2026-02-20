# frozen_string_literal: true

module Y
  class Snapshot
    # Decode a snapshot from a binary encoded array
    #
    # @param data [::Array<Integer>] Binary encoded snapshot
    # @return [Y::Snapshot]
    def self.decode(data)
      ysnapshot_decode_v1(data)
    end

    # Encode this snapshot to a binary array
    #
    # @return [::Array<Integer>]
    def encode
      ysnapshot_encode_v1
    end

    # @!method ysnapshot_encode_v1
    #   Encodes this snapshot to binary v1 format
    #
    # @return [::Array<Integer>]
    # @!visibility private

    # @!method self.ysnapshot_decode_v1(data)
    #   Decodes a snapshot from binary v1 format
    #
    # @param data [::Array<Integer>]
    # @return [Y::Snapshot]
    # @!visibility private
  end
end
