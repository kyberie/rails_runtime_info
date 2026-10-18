# frozen_string_literal: true

require "test_helper"

class RequestInfoTest < Minitest::Test
  LIMIT = RailsRuntimeInfo::RequestInfo::BODY_LIMIT

  class ShortReadInput
    attr_reader :lengths
    def initialize(bytes)
      @bytes = bytes.dup
      @lengths = []
    end
    def read(length)
      @lengths << length
      return nil if @bytes.empty?
      @bytes.slice!(0, [length, 3].min)
    end
    def close; raise "input closed"; end
    def rewind; raise "input rewound"; end
    def eof?; raise "eof? called"; end
    def pos; raise "pos called"; end
  end

  def test_headers_include_credentials_and_content_headers
    env = rack_env("", "HTTP_AUTHORIZATION" => "Basic abc", "HTTP_COOKIE" => "session=xyz", "HTTP_X_CUSTOM_TOKEN" => "secret", "CONTENT_TYPE" => "text/plain", "CONTENT_LENGTH" => "0")
    headers = RailsRuntimeInfo::RequestInfo.new(env).headers
    assert_equal "Basic abc", headers["Authorization"]
    assert_equal "session=xyz", headers["Cookie"]
    assert_equal "secret", headers["X-Custom-Token"]
    assert_equal "text/plain", headers["Content-Type"]
    assert_equal "0", headers["Content-Length"]
  end

  def test_url_and_metadata_retain_query_and_raw_uri
    env = rack_env("", "SCRIPT_NAME" => "/mounted", "REQUEST_URI" => "/raw%20path?token=raw")
    info = RailsRuntimeInfo::RequestInfo.new(env)
    assert_equal "https://app.internal/mounted/_internal/diagnostics?token=visible", info.reconstructed_url
    assert_equal "/raw%20path?token=raw", info.metadata["REQUEST_URI"]
  end

  def test_url_ipv6_fallback_nondefault_port
    env = rack_env("", "HTTP_HOST" => nil, "SERVER_NAME" => "::1", "SERVER_PORT" => "8443")
    assert_equal "https://[::1]:8443/_internal/diagnostics?token=visible", RailsRuntimeInfo::RequestInfo.new(env).reconstructed_url
  end

  def test_missing_input
    assert_equal({ "present" => false }, RailsRuntimeInfo::RequestInfo.new({}).body)
  end

  def test_empty_body
    result = RailsRuntimeInfo::RequestInfo.new(rack_env).body
    assert_equal 0, result["bytes_read"]
    assert_equal "", result["data"]
    refute result["truncated"]
  end

  def test_exact_limit_is_not_truncated
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("a" * LIMIT)).body
    assert_equal LIMIT, result["returned_bytes"]
    assert_equal LIMIT, result["bytes_read"]
    refute result["truncated"]
  end

  def test_limit_plus_one_and_no_drain
    input = StringIO.new("a" * (LIMIT + 400))
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("", "rack.input" => input)).body
    assert result["truncated"]
    assert_equal LIMIT, result["returned_bytes"]
    assert_equal LIMIT + 1, result["bytes_read"]
    assert_equal LIMIT + 1, input.pos
    refute input.closed?
  end

  def test_short_reads_without_optional_io_methods
    input = ShortReadInput.new("abcdefg")
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("", "rack.input" => input)).body
    assert_equal "abcdefg", result["data"]
    assert_equal [LIMIT + 1, LIMIT - 2, LIMIT - 5, LIMIT - 6], input.lengths
  end

  def test_binary_content_round_trips
    bytes = "abc\x00\xff\xfe".b
    result = RailsRuntimeInfo::RequestInfo.new(rack_env(bytes)).body
    assert_equal "base64", result["encoding"]
    assert_equal bytes, result["data"].unpack("m").first
  end

  def test_truncated_multibyte_character_round_trips
    bytes = ("a" * (LIMIT - 1)) + "\xc3\xa9".b
    result = RailsRuntimeInfo::RequestInfo.new(rack_env(bytes)).body
    assert result["truncated"]
    assert_equal "base64", result["encoding"]
    assert_equal bytes.byteslice(0, LIMIT), result["data"].unpack("m").first
  end

  def test_already_consumed_stream_is_not_rewound
    input = StringIO.new("prefixsuffix"); input.read(6)
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("", "rack.input" => input)).body
    assert_equal "suffix", result["data"]
  end

  def test_declared_content_length_is_not_trusted_for_truncation
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("body", "CONTENT_LENGTH" => "99999999")).body
    assert_equal 4, result["bytes_read"]
    refute result["truncated"]
  end

  def test_broken_input_return_type
    input = Object.new
    def input.read(_); 123; end
    assert_raises(TypeError) { RailsRuntimeInfo::RequestInfo.new(rack_env("", "rack.input" => input)).body }
  end

  def test_broken_input_ignoring_read_length
    input = Object.new
    def input.read(length); "a" * (length + 1); end
    assert_raises(IOError) { RailsRuntimeInfo::RequestInfo.new(rack_env("", "rack.input" => input)).body }
  end
  def test_cached_body_is_used_without_reading_input
    input = Object.new
    def input.read(_); raise "must not read cached input"; end
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("", "RAW_POST_DATA" => "cached", "rack.input" => input)).body
    assert_equal "cached", result["data"]
    assert_equal "RAW_POST_DATA", result["source"]
    assert_equal 0, result["bytes_read"]
    assert_equal 6, result["cached_bytes"]
  end

  def test_cached_binary_body_remains_bounded_and_lossless
    cached = "\xff".b * (LIMIT + 5)
    result = RailsRuntimeInfo::RequestInfo.new(rack_env("", "RAW_POST_DATA" => cached)).body
    assert result["truncated"]
    assert_equal "base64", result["encoding"]
    assert_equal cached.byteslice(0, LIMIT), result["data"].unpack("m").first
  end

end
