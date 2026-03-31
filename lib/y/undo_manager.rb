# frozen_string_literal: true

require "json"

module Y
  # UndoManager tracks changes and provides undo/redo functionality.
  #
  # The UndoManager manages an undo stack and redo stack of changes. It can be
  # configured to track specific origins and provides methods to navigate through
  # the history of changes.
  #
  # @example
  #   doc = Y::Doc.new
  #   manager = doc.get_undo_manager("my manager")
  #
  #   manager.include_origin("user")
  #   # ... make changes ...
  #   manager.undo if manager.can_undo?
  #   manager.redo if manager.can_redo?
  class UndoManager
    # Add an origin to the set of tracked origins.
    #
    # @param origin [String, Array<Integer>] the origin identifier to track
    # @return [void]
    #
    # @example Track changes from "user" origin
    #   manager.include_origin("user")
    def include_origin(origin)
      origin_bytes = origin.is_a?(String) ? origin.bytes : origin
      yundo_manager_include_origin(origin_bytes)
    end

    # Undo the last tracked change.
    #
    # @return [Boolean] true if a change was undone, false if undo stack is empty
    #
    # @example Undo the last change
    #   manager.undo
    def undo
      yundo_manager_undo
    end

    # Redo the last undone change.
    #
    # @return [Boolean] true if a change was redone, false if redo stack is empty
    #
    # @example Redo the last undone change
    #   manager.redo
    def redo
      yundo_manager_redo
    end

    # Check if there are changes to undo.
    #
    # @return [Boolean] true if there are changes to undo
    #
    # @example Check before undoing
    #   manager.undo if manager.can_undo?
    def can_undo?
      yundo_manager_can_undo
    end

    # Check if there are changes to redo.
    #
    # @return [Boolean] true if there are changes to redo
    #
    # @example Check before redoing
    #   manager.redo if manager.can_redo?
    def can_redo?
      yundo_manager_can_redo
    end

    # Force a stack item boundary.
    #
    # This creates a new item on the undo stack, even if no changes have
    # occurred since the last reset.
    #
    # @return [void]
    #
    # @example Force a boundary
    #   manager.reset
    def reset
      yundo_manager_reset
    end

    # Clear both undo and redo stacks.
    #
    # This removes all history from the undo and redo stacks.
    #
    # @return [void]
    #
    # @example Clear all history
    #   manager.clear
    def clear
      yundo_manager_clear
    end

    # Get the number of items on the undo stack.
    #
    # @return [Integer] number of items on the undo stack
    #
    # @example Check undo stack size
    #   manager.undo_stack_length
    def undo_stack_length
      yundo_manager_undo_stack_length
    end

    # Get the number of items on the redo stack.
    #
    # @return [Integer] number of items on the redo stack
    #
    # @example Check redo stack size
    #   manager.redo_stack_length
    def redo_stack_length
      yundo_manager_redo_stack_length
    end

    # Get all undo stack metadata as parsed JSON objects.
    #
    # Each item on the undo stack may have associated metadata. This method
    # retrieves all metadata and parses it from JSON format.
    #
    # @return [Array<Hash>] metadata for each undo stack item
    #
    # @example Get undo stack metadata
    #   metadata = manager.undo_stack
    #   metadata.each { |m| puts m }
    def undo_stack
      yundo_manager_undo_stack_metas.map do |bytes|
        raw = bytes.pack("C*")
        raw.empty? ? {} : JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
    end

    # Get all redo stack metadata as parsed JSON objects.
    #
    # Each item on the redo stack may have associated metadata. This method
    # retrieves all metadata and parses it from JSON format.
    #
    # @return [Array<Hash>] metadata for each redo stack item
    #
    # @example Get redo stack metadata
    #   metadata = manager.redo_stack
    #   metadata.each { |m| puts m }
    def redo_stack
      yundo_manager_redo_stack_metas.map do |bytes|
        raw = bytes.pack("C*")
        raw.empty? ? {} : JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end
    end

    # Set metadata on the most recent undo stack item.
    #
    # The metadata will be JSON-encoded if provided as a Hash.
    #
    # @param meta [Hash, String] metadata (will be JSON-encoded if Hash)
    # @return [void]
    #
    # @example Set metadata as a hash
    #   manager.set_meta({action: "edit", timestamp: Time.now})
    #
    # @example Set metadata as JSON string
    #   manager.set_meta('{"action":"edit"}')
    def set_meta(meta)
      json = meta.is_a?(String) ? meta : JSON.generate(meta)
      yundo_manager_set_last_undo_meta(json.bytes)
    end

    # @!method yundo_manager_include_origin(origin_bytes)
    #   Add an origin to track.
    #
    # @param origin_bytes [Array<Integer>] byte array for origin
    # @return [void]
    # @!visibility private

    # @!method yundo_manager_undo
    #   Undo the last change.
    #
    # @return [Boolean]
    # @!visibility private

    # @!method yundo_manager_redo
    #   Redo the last undone change.
    #
    # @return [Boolean]
    # @!visibility private

    # @!method yundo_manager_can_undo
    #   Check if undo is available.
    #
    # @return [Boolean]
    # @!visibility private

    # @!method yundo_manager_can_redo
    #   Check if redo is available.
    #
    # @return [Boolean]
    # @!visibility private

    # @!method yundo_manager_reset
    #   Force a stack boundary.
    #
    # @return [void]
    # @!visibility private

    # @!method yundo_manager_clear
    #   Clear both stacks.
    #
    # @return [void]
    # @!visibility private

    # @!method yundo_manager_undo_stack_length
    #   Get undo stack length.
    #
    # @return [Integer]
    # @!visibility private

    # @!method yundo_manager_redo_stack_length
    #   Get redo stack length.
    #
    # @return [Integer]
    # @!visibility private

    # @!method yundo_manager_undo_stack_metas
    #   Get undo stack metadata as byte arrays.
    #
    # @return [Array<Array<Integer>>]
    # @!visibility private

    # @!method yundo_manager_redo_stack_metas
    #   Get redo stack metadata as byte arrays.
    #
    # @return [Array<Array<Integer>>]
    # @!visibility private

    # @!method yundo_manager_set_last_undo_meta(meta_bytes)
    #   Set metadata on the last undo item.
    #
    # @param meta_bytes [Array<Integer>] byte array for metadata
    # @return [void]
    # @!visibility private
  end
end
