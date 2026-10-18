# frozen_string_literal: true

module RailsRuntimeInfo
  # Request-local, ordered inclusion rules. Later rules for a parent replace
  # all previous rules below that parent. Never examines application objects.
  class Selection
    CATEGORIES = %w[gem_version time_utc process server gems environment loaded_features load_path errors gc yjit runtime application request].freeze
    DEFAULT = "+all,-loaded_features,-load_path,-gems,-environment".freeze
    MAX_BYTES = 8192
    MAX_RULES = 128
    MAX_DEPTH = 24

    class Invalid < StandardError; end

    class Node
      attr_accessor :enabled
      attr_reader :children

      def initialize(enabled = nil)
        @enabled = enabled
        @children = {}
      end
    end
    private_constant :Node

    def initialize(query_string = nil)
      @root = Node.new(false)
      apply_expression(DEFAULT)
      @query_bytes = 0
      @query_rules = 0
      read_query(query_string) if query_string.kind_of?(String) && !query_string.empty?
    end

    # A parent must be collected when any of its descendants is requested,
    # even when the parent was disabled by an earlier -all or -parent rule.
    def requested?(path)
      node, inherited = state_at(path)
      subtree_enabled?(node, inherited)
    end

    # Only called on our newly created, normalized JSON tree. Prune in place to
    # avoid retaining a second copy. Arrays and scalar values are atomic leaves.
    def filter!(document)
      prune_hash!(document, "")
      document
    end

    private

    def read_query(query)
      require "uri"
      # Do not invoke Rack/Rails parameter parsers, parse a body, or decode the
      # values of unrelated query parameters. Repeated what values are ordered.
      String.new(query).force_encoding(Encoding::BINARY).each_line("&") do |pair|
        raw_key, raw_value = pair.chomp("&").split("=", 2)
        next unless raw_key
        begin
          key = URI.decode_www_form_component(raw_key)
        rescue ArgumentError
          next
        end
        next unless key == "what"
        raw_value ||= ""
        raise Invalid, "what exceeds #{MAX_BYTES} decoded bytes" if raw_value.bytesize > MAX_BYTES * 3
        begin
          value = URI.decode_www_form_component(raw_value)
        rescue ArgumentError
          raise Invalid, "what contains invalid percent encoding"
        end
        @query_bytes += value.bytesize
        raise Invalid, "what exceeds #{MAX_BYTES} decoded bytes" if @query_bytes > MAX_BYTES
        unless value.ascii_only? && !value.match(/[\x00-\x1f\x7f]/)
          raise Invalid, "what must contain printable ASCII selector text"
        end
        next if value.empty?
        @query_rules += value.count(",") + 1
        raise Invalid, "what exceeds #{MAX_RULES} rules" if @query_rules > MAX_RULES
        apply_expression(value)
      end
    end

    def apply_expression(expression)
      expression.split(",", -1).each do |token|
        match = /\A([+-])([A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*)\z/.match(token.strip)
        unless match
          raise Invalid, "each what rule needs + or - and a category or dotted path; URL-encode + as %2B"
        end
        enabled = match[1] == "+"
        path = match[2]
        parts = path.split(".")
        if path == "all"
          node = @root
        else
          raise Invalid, "unknown what category: #{parts.first}" unless CATEGORIES.include?(parts.first)
          raise Invalid, "what paths exceed #{MAX_DEPTH} components" if parts.length > MAX_DEPTH
          node = @root
          parts.each { |part| node = (node.children[part] ||= Node.new) }
        end
        node.enabled = enabled
        node.children.clear
      end
    end

    def state_at(path)
      node = @root
      inherited = node.enabled
      path.split(".").each do |part|
        node = node && node.children[part]
        inherited = node.enabled if node && !node.enabled.nil?
      end
      [node, inherited]
    end

    def subtree_enabled?(node, inherited)
      return true if inherited
      node && node.children.any? do |_, child|
        state = child.enabled.nil? ? inherited : child.enabled
        subtree_enabled?(child, state)
      end
    end

    def prune_hash!(hash, prefix)
      hash.delete_if do |key, value|
        # Rack keys such as action_dispatch.request_id remain flat in JSON,
        # but their dots participate in the same selector path notation.
        path = prefix.empty? ? key : "#{prefix}.#{key}"
        node, enabled = state_at(path)
        if !subtree_enabled?(node, enabled)
          true
        elsif value.instance_of?(Hash)
          prune_hash!(value, path)
          !enabled && value.empty?
        else
          !enabled
        end
      end
    end
  end
end
