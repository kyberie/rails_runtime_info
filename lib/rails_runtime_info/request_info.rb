# frozen_string_literal: true

module RailsRuntimeInfo
  class RequestInfo
    BODY_LIMIT = 100 * 1024
    CGI_KEYS = %w[REQUEST_METHOD REQUEST_URI RAW_URI ORIGINAL_FULLPATH REQUEST_PATH SCRIPT_NAME PATH_INFO QUERY_STRING SERVER_NAME SERVER_PORT SERVER_PROTOCOL REMOTE_ADDR REMOTE_HOST REMOTE_PORT CONTENT_TYPE CONTENT_LENGTH HTTPS].freeze

    def initialize(env)
      @env = env
    end

    def metadata
      fields = {}
      CGI_KEYS.each { |key| fields[key] = @env[key] if @env.key?(key) }
      fields["rack.url_scheme"] = @env["rack.url_scheme"]
      fields
    end

    def headers
      result = {}
      @env.each do |key, value|
        next unless key.kind_of?(String)
        name = if key.start_with?("HTTP_")
          key[5..-1].split("_").map { |word| word.capitalize }.join("-")
        elsif key == "CONTENT_TYPE"
          "Content-Type"
        elsif key == "CONTENT_LENGTH"
          "Content-Length"
        end
        result[name] = value if name
      end
      result
    end

    def reconstructed_url
      scheme = string_value("rack.url_scheme")
      return nil unless scheme
      authority = string_value("HTTP_HOST")
      if !authority || authority.empty?
        authority = string_value("SERVER_NAME")
        return nil unless authority
        authority = "[#{authority}]" if authority.include?(":") && !authority.start_with?("[")
        port = string_value("SERVER_PORT")
        default_port = (scheme == "http" && port == "80") || (scheme == "https" && port == "443")
        authority += ":#{port}" if port && !port.empty? && !default_port
      end
      path = (string_value("SCRIPT_NAME") || "") + (string_value("PATH_INFO") || "")
      path = "/" if path.empty?
      query = string_value("QUERY_STRING")
      "#{scheme}://#{authority}#{path}" + (query && !query.empty? ? "?#{query}" : "")
    end

    def body
      # Rails may already have read the body. Reuse at most the bounded prefix
      # without copying the whole cached String or touching the input again.
      cached = @env["RAW_POST_DATA"]
      if cached.kind_of?(String)
        data = String.new(cached.byteslice(0, BODY_LIMIT))
        result = encoded_body(data, 0, cached.bytesize > BODY_LIMIT)
        result["source"] = "RAW_POST_DATA"
        result["cached_bytes"] = cached.bytesize
        result["position"] = "already-buffered body; rack.input not read"
        return result
      end
      input = @env["rack.input"]
      return { "present" => false } if input.nil?
      data = String.new.force_encoding(Encoding::BINARY)
      while data.bytesize < BODY_LIMIT + 1
        remaining = BODY_LIMIT + 1 - data.bytesize
        chunk = input.read(remaining)
        break if chunk.nil?
        raise TypeError, "rack.input.read did not return a String" unless chunk.kind_of?(String)
        raise IOError, "rack.input.read exceeded requested length" if chunk.bytesize > remaining
        break if chunk.empty?
        data << String.new(chunk).force_encoding(Encoding::BINARY)
      end
      bytes_read = data.bytesize
      truncated = bytes_read > BODY_LIMIT
      data = data.byteslice(0, BODY_LIMIT) if truncated
      result = encoded_body(data, bytes_read, truncated)
      result["source"] = "rack.input"
      result["position"] = "read from current rack.input position; not rewound or drained"
      result
    end

    private

    def encoded_body(data, bytes_read, truncated)
      utf8 = data.dup.force_encoding(Encoding::UTF_8)
      textual = utf8.valid_encoding? && !utf8.match(/[\x00-\x08\x0b\x0c\x0e-\x1f]/)
      {
        "present" => true,
        "limit_bytes" => BODY_LIMIT,
        "bytes_read" => bytes_read,
        "returned_bytes" => data.bytesize,
        "truncated" => truncated,
        "encoding" => textual ? "utf-8" : "base64",
        "data" => textual ? utf8 : [data].pack("m0")
      }
    end

    def string_value(key)
      value = @env[key]
      value.kind_of?(String) ? String.new(value) : nil
    end
  end
end
