# frozen_string_literal: true

module RailsRuntimeInfo
  # Copy primitives into ordinary JSON-compatible objects. Never call inspect,
  # as_json, to_json, to_h, or arbitrary to_s methods on application objects.
  # In particular, Hash/Array subclasses (including lazy session wrappers) are
  # opaque. String subclasses are copied using the core String implementation.
  class Normalizer
    MAX_DEPTH = 24
    MAX_NODES = 100_000
    REQUEST_CACHE_KEYS = %w[RAW_POST_DATA rack.request.form_vars rack.request.form_hash rack.request.form_pairs action_dispatch.request.request_parameters action_dispatch.request.parameters].freeze

    def initialize(options = {})
      @omit_request_caches = options[:omit_request_caches]
      @ancestors = {}
      @nodes = 0
    end

    def call(value, depth = 0)
      @nodes += 1
      return marker("limit", "reason" => "node_limit") if @nodes > MAX_NODES
      return marker("limit", "reason" => "depth_limit") if depth > MAX_DEPTH

      klass = Object.instance_method(:class).bind(value).call
      return nil if klass == NilClass
      return value if klass == TrueClass || klass == FalseClass || klass == Integer
      return normalize_float(value) if klass == Float
      return normalize_string(String.new(value)) if klass <= String
      return value.to_s if klass == Symbol
      return container(value, depth) if klass == Hash || klass == Array
      marker("object", "class" => Support.class_name(value))
    rescue StandardError, NotImplementedError => error
      marker("unavailable", "class" => Support.class_name(error))
    end

    private

    def marker(type, fields = {})
      { "_type" => type }.merge(fields)
    end

    def normalize_float(value)
      return value if value.finite?
      text = value.nan? ? "NaN" : (value > 0 ? "Infinity" : "-Infinity")
      marker("float", "value" => text)
    end

    def normalize_string(value)
      encoding = value.encoding.name
      text = value.dup.force_encoding(Encoding::UTF_8)
      return text if text.valid_encoding?
      marker("binary", "encoding" => encoding, "base64" => [value].pack("m0"))
    end

    def container(value, depth)
      id = value.object_id
      return marker("cycle") if @ancestors[id]
      @ancestors[id] = true
      begin
        if value.instance_of?(Array)
          copy_array(value, depth)
        else
          copy_hash(value, depth)
        end
      ensure
        @ancestors.delete(id)
      end
    end

    def copy_array(value, depth)
      result = []
      value.each do |item|
        if @nodes >= MAX_NODES
          result << marker("limit", "reason" => "node_limit")
          break
        end
        result << call(item, depth + 1)
      end
      result
    end

    def request_cache_descriptor(value)
      fields = { "class" => Support.class_name(value), "note" => "not duplicated here; see bounded request.body" }
      klass = Object.instance_method(:class).bind(value).call
      fields["bytesize"] = value.bytesize if klass <= String
      fields["entries"] = value.size if klass == Array || klass == Hash
      marker("request_body_cache", fields)
    end

    def copy_hash(value, depth)
      result = {}
      entries = []
      ordinary_keys = true
      value.each do |key, item|
        if @nodes >= MAX_NODES
          entries << [marker("limit", "reason" => "node_limit"), nil]
          ordinary_keys = false
          break
        end
        normalized_key = key.instance_of?(Integer) ? key.to_s : call(key, depth + 1)
        normalized_value = if @omit_request_caches && key.kind_of?(String) && REQUEST_CACHE_KEYS.include?(key)
          request_cache_descriptor(item)
        else
          call(item, depth + 1)
        end
        entries << [normalized_key, normalized_value]
        if normalized_key.instance_of?(String) && !result.key?(normalized_key)
          result[normalized_key] = normalized_value
        else
          ordinary_keys = false
        end
      end
      # Preserve binary/non-string keys and symbol/string key collisions.
      ordinary_keys ? result : marker("map", "entries" => entries)
    end
  end
end
