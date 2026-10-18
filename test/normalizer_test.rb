# frozen_string_literal: true

require "test_helper"

class NormalizerTest < Minitest::Test
  class Hostile
    def inspect; raise "inspect called"; end
    def to_s; raise "to_s called"; end
    def as_json(*); raise "as_json called"; end
    def to_json(*); raise "to_json called"; end
    def to_h; raise "to_h called"; end
  end

  class LazyHash < Hash
    def each; raise "lazy hash traversed"; end
    def to_h; raise "lazy hash converted"; end
  end

  class LazyArray < Array
    def each; raise "lazy array traversed"; end
  end

  def normalize(value)
    RailsRuntimeInfo::Normalizer.new.call(value)
  end

  def test_primitives_and_full_nested_hash
    input = { :count => 17, "values" => [true, false, nil, 1.25, "text"] }
    assert_equal({ "count" => 17, "values" => [true, false, nil, 1.25, "text"] }, normalize(input))
    assert_equal input, { :count => 17, "values" => [true, false, nil, 1.25, "text"] }
  end

  def test_no_application_serialization_hooks
    result = normalize(Hostile.new)
    assert_equal "object", result["_type"]
    assert_equal "NormalizerTest::Hostile", result["class"]
    JSON.pretty_generate(result)
  end

  def test_lazy_container_subclasses_are_opaque
    assert_equal "object", normalize(LazyHash.new)["_type"]
    assert_equal "object", normalize(LazyArray.new)["_type"]
  end

  def test_string_subclass_becomes_plain_string
    input = Class.new(String).new("production")
    output = normalize(input)
    assert_instance_of String, output
    assert_equal "production", output
    refute_same input, output
  end

  def test_invalid_utf8_is_preserved_as_base64
    bytes = "\xff\x00\xfe".b
    output = normalize(bytes)
    assert_equal "binary", output["_type"]
    assert_equal bytes, output["base64"].unpack("m").first
    assert_equal Encoding::ASCII_8BIT, bytes.encoding
  end

  def test_valid_utf8_in_binary_string_is_not_corrupted
    bytes = "\xc3\xa9".b
    output = normalize(bytes)
    assert_equal "\u00e9", output
    assert_equal Encoding::UTF_8, output.encoding
  end

  def test_non_finite_floats_do_not_break_json
    values = normalize([Float::NAN, Float::INFINITY, -Float::INFINITY])
    assert_equal ["NaN", "Infinity", "-Infinity"], values.map { |v| v["value"] }
    JSON.pretty_generate(values)
  end

  def test_cycle_is_bounded
    value = {}; value["self"] = value
    assert_equal "cycle", normalize(value)["self"]["_type"]
  end

  def test_shared_noncyclic_values_are_not_mistaken_for_cycles
    child = { "a" => 1 }
    assert_equal [child, child], normalize([child, child])
  end

  def test_depth_limit
    value = []; 40.times { value = [value] }
    encoded = JSON.generate(normalize(value))
    assert_includes encoded, "depth_limit"
  end

  def test_node_limit
    with_constant(RailsRuntimeInfo::Normalizer, :MAX_NODES, 8) do
      output = normalize(Array.new(100, 1))
      assert_includes JSON.generate(output), "node_limit"
      assert_operator output.size, :<, 100
    end
  end

  def test_non_string_and_colliding_keys_are_preserved
    input = { :one => 1, "one" => 2, "\xff".b => 3 }
    output = normalize(input)
    assert_equal "map", output["_type"]
    assert_equal 3, output["entries"].size
    assert_equal [1, 2, 3], output["entries"].map { |pair| pair.last }
    JSON.pretty_generate(output)
  end
  def test_integer_heap_identifiers_become_json_object_keys
    assert_equal({ "0" => { "size" => 10 } }, normalize({ 0 => { :size => 10 } }))
  end

end
