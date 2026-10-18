# frozen_string_literal: true

require "test_helper"

class SelectionTest < Minitest::Test
  def select(expression, document)
    selection = RailsRuntimeInfo::Selection.new(URI.encode_www_form("what" => expression))
    selection.filter!(document)
  end

  def test_exact_defaults_and_output_order
    _, _, data = response
    assert_equal %w[gem_version time_utc process server errors gc yjit runtime application request], data.keys
  end

  def test_all_restores_every_category_and_requested_tail
    _, _, data = response(what_env("+all"))
    assert_equal RailsRuntimeInfo::Selection::CATEGORIES, data.keys
    assert_equal %w[gc yjit runtime application request], data.keys.last(5)
    assert_kind_of Hash, data["environment"]
    assert_kind_of Array, data["loaded_features"]
    assert_kind_of Array, data["load_path"]
    assert_equal ["activated"], data["gems"].keys
  end

  def test_expression_is_applied_after_defaults_not_instead_of_them
    _, _, data = response(what_env("+gems"))
    assert data.key?("gems")
    assert data.key?("request")
    refute data.key?("environment")
    refute data.key?("loaded_features")
    refute data.key?("load_path")
  end

  def test_all_negative_returns_empty_object
    status, _, data = response(what_env("-all"))
    assert_equal 200, status
    assert_equal({}, data)
  end

  def test_left_to_right_top_level
    _, _, data = response(what_env("-all,+gc,-gc,+request"))
    assert_equal ["request"], data.keys
    assert data["request"].key?("headers")
  end

  def test_nested_exclusion_from_default_request
    _, _, data = response(what_env("+request,-request.rack_environment"))
    refute data["request"].key?("rack_environment")
    assert data["request"].key?("headers")
    assert data.key?("runtime")
  end

  def test_nested_inclusion_recreates_parent_after_all_is_disabled
    _, _, data = response(what_env("-all,+request.headers"))
    assert_equal ["request"], data.keys
    assert_equal ["headers"], data["request"].keys
    assert_equal "app.internal", data["request"]["headers"]["Host"]
  end

  def test_later_parent_inclusion_clears_prior_child_exclusion
    document = { "request" => { "headers" => { "Host" => "test" }, "body" => "data" } }
    assert_equal document, select("-all,+request,-request.body,+request", Marshal.load(Marshal.dump(document)))
  end

  def test_later_parent_exclusion_clears_prior_child_inclusion
    assert_equal({}, select("-all,+request.headers,-request", { "request" => { "headers" => {} } }))
  end

  def test_later_all_clears_all_child_exclusions
    document = { "request" => { "body" => "data" }, "environment" => { "K" => "V" } }
    assert_equal document, select("-request.body,+all", Marshal.load(Marshal.dump(document)))
  end

  def test_child_reinclusion_does_not_resurrect_siblings
    data = select("-all,+request,-request,+request.headers.Host", { "request" => { "headers" => { "Host" => "test", "Cookie" => "cookie" }, "body" => "body" } })
    assert_equal({ "request" => { "headers" => { "Host" => "test" } } }, data)
  end

  def test_complete_gc_api_called_but_only_requested_stat_returned
    stats = { :count => 42, :other => 7 }
    GC.stub(:stat, stats) do
      _, _, data = response(what_env("-all,+gc.stat.count"))
      assert_equal({ "gc" => { "stat" => { "count" => 42 } } }, data)
    end
  end

  def test_select_yjit_flag_without_selecting_available_or_statistics
    jit = Module.new
    def jit.enabled?; true; end
    def jit.runtime_stats; raise "unrequested stats called"; end
    vm = Module.new; vm.const_set(:YJIT, jit)
    with_constant(Object, :RubyVM, vm) do
      _, _, data = response(what_env("-all,+yjit.enabled"))
      assert_equal({ "yjit" => { "enabled" => true } }, data)
    end
  end

  def test_dotted_rack_keys_can_be_selected_but_stay_flat
    env = what_env("-all,+request.rack_environment.action_dispatch.request_id", "", "action_dispatch.request_id" => "trace-id")
    _, _, data = response(env)
    assert_equal({ "request" => { "rack_environment" => { "action_dispatch.request_id" => "trace-id" } } }, data)
  end

  def test_unknown_nested_keys_are_no_ops_not_schema_requirements
    _, _, data = response(what_env("-all,+request.not_installed"))
    assert_equal({}, data)
  end

  def test_arrays_are_atomic_and_not_projected_by_index
    data = { "gems" => { "activated" => [{ "name" => "ruby" }] } }
    assert_equal({}, select("-all,+gems.activated.0.name", data))
  end

  def test_error_section_is_selectable
    _, _, data = response(what_env("-all,+errors"))
    assert_equal({ "errors" => {} }, data)
  end

  def test_repeated_what_values_apply_in_wire_order
    query = URI.encode_www_form([["what", "-all,+gc"], ["what", "-gc,+request.headers"]])
    _, _, data = response(rack_env("", "QUERY_STRING" => query))
    assert_equal ["request"], data.keys
    assert_equal ["headers"], data["request"].keys
  end

  def test_absent_and_empty_what_use_defaults
    ["", "what=", "what", "else=%ZZ"].each do |query|
      status, _, data = response(rack_env("", "QUERY_STRING" => query))
      assert_equal 200, status
      assert data.key?("request")
      refute data.key?("environment")
    end
  end

  def test_percent_encoded_key_and_comma
    _, _, data = response(rack_env("", "QUERY_STRING" => "%77hat=-all%2C%2Brequest.headers"))
    assert_equal ["request"], data.keys
    assert_equal ["headers"], data["request"].keys
  end

  def test_unrelated_malformed_values_are_not_parsed
    _, _, data = response(rack_env("", "QUERY_STRING" => "other=%QQ&%broken=abc&what=-all%2C%2Bruntime.ruby_version"))
    assert_equal({ "runtime" => { "ruby_version" => RUBY_VERSION } }, data)
  end

  def test_unescaped_plus_is_rejected_with_encoding_hint
    status, _, data = response(rack_env("", "QUERY_STRING" => "what=+request"))
    assert_equal 400, status
    assert_equal "invalid_what", data["error"]
    assert_includes data["message"], "%2B"
  end

  def test_required_prefix_empty_tokens_and_malformed_paths
    %w[all request + - +request,,+gc +request, ,+request +request. +request..body +all.request +made_up].each do |expression|
      status, _, data = response(what_env(expression))
      assert_equal 400, status, expression
      assert_equal "invalid_what", data["error"], expression
    end
  end

  def test_whitespace_between_rules_is_accepted_after_decoding
    _, _, data = response(what_env(" -all, +request.headers "))
    assert_equal ["request"], data.keys
    assert_equal ["headers"], data["request"].keys
  end

  def test_invalid_percent_encoding_and_non_ascii_fail_cleanly
    ["what=%GG", "what=%FF", "what=%2Brequest%00"].each do |query|
      status, _, data = response(rack_env("", "QUERY_STRING" => query))
      assert_equal 400, status
      assert_equal "invalid_what", data["error"]
    end
  end

  def test_selector_byte_and_rule_limits
    ["+request" + " " * RailsRuntimeInfo::Selection::MAX_BYTES, Array.new(RailsRuntimeInfo::Selection::MAX_RULES + 1, "+gc").join(",")].each do |expression|
      status, _, data = response(what_env(expression))
      assert_equal 400, status
      assert_equal "invalid_what", data["error"]
    end
  end

  def test_selector_depth_limit
    status, _, data = response(what_env("+request" + ".x" * RailsRuntimeInfo::Selection::MAX_DEPTH))
    assert_equal 400, status
    assert_equal "invalid_what", data["error"]
  end

  def test_disabled_top_level_collectors_do_not_run
    forbidden = proc { raise "unselected collector ran" }
    GC.stub(:stat, forbidden) do
      with_instance_method(RailsRuntimeInfo::Snapshot, :application, forbidden) do
        with_instance_method(RailsRuntimeInfo::Snapshot, :process_info, forbidden) do
          with_instance_method(RailsRuntimeInfo::Snapshot, :gem_info, forbidden) do
            status, _, data = response(what_env("-all,+request.headers,+errors"))
            assert_equal 200, status
            assert_equal({}, data["errors"])
            assert_equal %w[errors request], data.keys
          end
        end
      end
    end
  end

  def test_default_omits_expensive_lists_without_reading_them
    forbidden = proc { raise "default must not collect this" }
    ENV.stub(:to_h, forbidden) do
      with_instance_method(RailsRuntimeInfo::Snapshot, :gem_info, forbidden) do
        _, _, data = response
        refute data.key?("environment")
        refute data.key?("gems")
        refute data["errors"].key?("environment")
        refute data["errors"].key?("gems")
      end
    end
  end

  def test_excluding_body_does_not_read_input
    input = StringIO.new("must remain unread")
    _, _, data = response(what_env("-request.body", "", "rack.input" => input))
    assert_equal 0, input.pos
    refute data["request"].key?("body")
    refute data["errors"].key?("request.body")
  end

  def test_excluding_environment_does_not_normalize_its_entries
    original_new = RailsRuntimeInfo::Normalizer.method(:new)
    replacement = proc do |options = {}|
      raise "must not normalize Rack environment" if options[:request_environment]
      original_new.call(options)
    end
    RailsRuntimeInfo::Normalizer.stub(:new, replacement) do
      _, _, data = response(what_env("-request.rack_environment"))
      refute data["request"].key?("rack_environment")
      refute data["errors"].key?("request.rack_environment")
    end
  end

  def test_excluding_linux_skips_file_reads
    RailsRuntimeInfo::LinuxProcess.stub(:read, proc { |*_| raise "must not read proc" }) do
      _, _, data = response(what_env("-process.linux"))
      assert_equal Process.pid, data["process"]["pid"]
      refute data["process"].key?("linux")
      refute data["errors"].keys.any? { |key| key.start_with?("process.linux") }
    end
  end

  def test_invalid_selection_does_not_collect_or_read_body
    input = StringIO.new("unread")
    GC.stub(:stat, proc { raise "must not collect" }) do
      status, headers, data, text = response(what_env("request", "", "rack.input" => input))
      assert_equal 400, status
      assert_equal 0, input.pos
      assert_equal "invalid_what", data["error"]
      assert_equal text.bytesize.to_s, headers["content-length"]
      assert_equal "no-store", headers["cache-control"]
    end
  end

  def test_invalid_selection_head_response_is_still_bodyless
    status, headers, data, text = response(what_env("request", "", "REQUEST_METHOD" => "HEAD"))
    assert_equal 400, status
    assert_nil data
    assert_equal "", text
    assert_operator headers["content-length"].to_i, :>, 0
  end

  def test_json_failure_on_invalid_selection_has_last_resort_fallback
    JSON.stub(:pretty_generate, proc { |*_| raise "JSON unavailable" }) do
      status, _, data = response(what_env("request"))
      assert_equal 500, status
      assert data["error"]
    end
  end

  def test_selection_state_is_not_retained_between_requests
    _, _, first = response(what_env("-all,+request.headers"))
    _, _, second = response
    assert_equal ["request"], first.keys
    assert second.key?("gc")
    assert second["request"].key?("rack_environment")
  end
  def test_selection_matches_an_independent_left_to_right_reference
    document = {
      "request" => { "headers" => { "Host" => "example", "Cookie" => "cookie" }, "body" => "body", "rack_environment" => { "action_dispatch.request_id" => "id" } },
      "gc" => { "stat" => { "count" => 7, "other" => 8 } },
      "gems" => { "activated" => ["one"] }, "environment" => { "K" => "V" }
    }
    paths = %w[all request request.headers request.headers.Host request.body request.rack_environment request.rack_environment.action_dispatch request.rack_environment.action_dispatch.request_id gc gc.stat gc.stat.count gems gems.activated environment environment.K]
    random = Random.new(81731)
    100.times do
      rules = Array.new(16) { (random.rand(2).zero? ? "+" : "-") + paths[random.rand(paths.length)] }
      expression = rules.join(",")
      reference_rules = RailsRuntimeInfo::Selection::DEFAULT.split(",") + rules
      enabled = proc do |path|
        state = false
        reference_rules.each do |rule|
          prefix = rule[1..-1]
          state = rule[0] == "+" if prefix == "all" || path == prefix || path.start_with?(prefix + ".")
        end
        state
      end
      project = nil
      project = proc do |hash, prefix|
        hash.each_with_object({}) do |(key, value), result|
          path = prefix.empty? ? key : prefix + "." + key
          if value.instance_of?(Hash)
            child = project.call(value, path)
            result[key] = child if enabled.call(path) || !child.empty?
          elsif enabled.call(path)
            result[key] = value
          end
        end
      end
      expected = project.call(document, "")
      actual = select(expression, Marshal.load(Marshal.dump(document)))
      assert_equal expected, actual, expression
    end
  end

end
