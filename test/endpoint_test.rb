# frozen_string_literal: true

require "test_helper"
require "lockfile_test"

class EndpointTest < Minitest::Test
  def test_valid_response_and_headers
    status, headers, data, text = response
    assert_equal 200, status
    assert_equal "application/json; charset=utf-8", headers["content-type"]
    assert_equal "no-store", headers["cache-control"]
    assert_equal "nosniff", headers["x-content-type-options"]
    assert_equal text.bytesize.to_s, headers["content-length"]
    assert_equal headers.keys.map(&:downcase), headers.keys
    assert_equal RailsRuntimeInfo::VERSION, data["gem_version"]
    assert_match(/Z\z/, data["time_utc"])
  end

  def test_all_request_data_and_env_secrets_are_deliberately_returned
    with_environment("RAILS_RUNTIME_INFO_TEST_SECRET" => "plain-secret") do
      env = rack_env("payload", "HTTP_AUTHORIZATION" => "Basic xyz", "HTTP_COOKIE" => "secret=yes", "custom.object" => Object.new)
      _, _, data = response(env)
      assert_equal "plain-secret", data["environment"]["RAILS_RUNTIME_INFO_TEST_SECRET"]
      assert_equal "Basic xyz", data["request"]["headers"]["Authorization"]
      assert_equal "secret=yes", data["request"]["headers"]["Cookie"]
      assert_equal "token=visible", data["request"]["metadata"]["QUERY_STRING"]
      assert_equal "payload", data["request"]["body"]["data"]
      assert_equal "object", data["request"]["rack_environment"]["custom.object"]["_type"]
    end
  end

  def test_activated_and_locked_gems_are_separate
    Dir.mktmpdir do |directory|
      path = File.join(directory, "Gemfile")
      File.write(path, "raise 'must not evaluate'\n")
      File.write(path + ".lock", LockfileTest::LOCK)
      with_environment("BUNDLE_GEMFILE" => path) do
        _, _, data = response
        assert_equal 6, data["gems"]["locked"]["gems"].size
        assert_includes data["gems"]["activated"].map { |g| g["name"] }, "json"
        refute_includes data["gems"]["activated"].map { |g| g["name"] }, "internal"
        refute data["errors"].key?("gems.locked")
      end
    end
  end

  def test_body_failure_does_not_fail_other_sections
    input = Object.new
    def input.read(_); raise IOError, "body unavailable"; end
    status, _, data = response(rack_env("", "rack.input" => input))
    assert_equal 200, status
    assert_nil data["request"]["body"]
    assert_equal "IOError", data["errors"]["request.body"]["class"]
    assert_equal Process.pid, data["process"]["pid"]
    assert data["environment"].kind_of?(Hash)
  end

  def test_proc_failure_is_field_local
    RailsRuntimeInfo::LinuxProcess.stub(:read, proc { |*_| raise Errno::EACCES, "blocked" }) do
      status, _, data = response
      assert_equal 200, status
      assert_equal Process.pid, data["process"]["pid"]
      if RUBY_PLATFORM.include?("linux")
        assert_nil data["process"]["linux"]["status"]
        assert_equal "Errno::EACCES", data["errors"]["process.linux.status"]["class"]
      end
    end
  end

  def test_gc_failure_does_not_fail_other_gc_methods
    GC.stub(:stat, proc { raise "GC stat failed" }) do
      status, _, data = response
      assert_equal 200, status
      assert_nil data["gc"]["stat"]
      assert data["gc"].key?("latest_gc_info")
      assert_equal "RuntimeError", data["errors"]["gc.stat"]["class"]
    end
  end

  def test_gc_statistics_are_not_filtered
    full = { :new_future_counter => 123, :nested => { :x => 99 } }
    GC.stub(:stat, full) do
      _, _, data = response
      assert_equal({ "new_future_counter" => 123, "nested" => { "x" => 99 } }, data["gc"]["stat"])
    end
  end

  def test_yjit_absent
    with_constant(Object, :RubyVM, Module.new) do
      status, _, data = response
      assert_equal 200, status
      refute data["yjit"]["available"]
    end
  end

  def test_yjit_disabled_nil_statistics
    jit = Module.new
    def jit.enabled?; false; end
    def jit.runtime_stats; nil; end
    vm = Module.new; vm.const_set(:YJIT, jit)
    with_constant(Object, :RubyVM, vm) do
      _, _, data = response
      assert data["yjit"]["available"]
      refute data["yjit"]["enabled"]
      assert_nil data["yjit"]["runtime_stats"]
    end
  end

  def test_full_yjit_hash_with_nan
    jit = Module.new
    def jit.enabled?; true; end
    def jit.stats_enabled?; true; end
    def jit.runtime_stats; { :future_metric => 42, :ratio => Float::NAN }; end
    def jit.enable(*); raise "must not enable YJIT"; end
    def jit.reset_stats!; raise "must not reset YJIT"; end
    vm = Module.new; vm.const_set(:YJIT, jit)
    with_constant(Object, :RubyVM, vm) do
      _, _, data = response
      assert_equal 42, data["yjit"]["runtime_stats"]["future_metric"]
      assert_equal "NaN", data["yjit"]["runtime_stats"]["ratio"]["value"]
    end
  end

  def test_not_implemented_api_is_optional
    jit = Module.new
    def jit.enabled?; raise NotImplementedError; end
    def jit.runtime_stats; { :ok => 1 }; end
    vm = Module.new; vm.const_set(:YJIT, jit)
    with_constant(Object, :RubyVM, vm) do
      status, _, data = response
      assert_equal 200, status
      assert_equal "NotImplementedError", data["errors"]["yjit.enabled"]["class"]
      assert_equal 1, data["yjit"]["runtime_stats"]["ok"]
    end
  end

  def test_rails_51_style_config_without_newer_accessors
    config = Struct.new(:root, :eager_load, :cache_classes, :time_zone, :force_ssl, :log_level).new("/app", true, true, "UTC", true, :info)
    app = Object.new; app.instance_variable_set(:@config, config); app.instance_variable_set(:@initialized, true)
    rails = Module.new; rails.instance_variable_set(:@application, app); rails.instance_variable_set(:@_env, "production")
    def rails.application; raise "must not call Rails.application"; end
    def rails.root; raise "must not call Rails.root"; end
    with_constant(Object, :Rails, rails) do
      status, _, data = response
      assert_equal 200, status
      assert_equal "/app", data["application"]["root"]
      assert_equal "production", data["application"]["environment"]
      assert_equal true, data["application"]["cache_classes"]
      refute data["application"].key?("enable_reloading")
    end
  end

  def test_rails_is_not_instantiated
    rails = Module.new
    def rails.application; raise "lazy initialization attempted"; end
    with_constant(Object, :Rails, rails) do
      status, _, data = response
      assert_equal 200, status
      refute data["application"]["application_instantiated"]
    end
  end

  def test_optional_constants_are_not_autoloaded
    rails = Module.new
    rails.autoload(:Info, "/does/not/exist/never_load_rails_info")
    vm = Module.new; vm.autoload(:YJIT, "/does/not/exist/never_load_yjit")
    with_constant(Object, :Rails, rails) do
      with_constant(Object, :RubyVM, vm) do
        status, _, data = response
        assert_equal 200, status
        refute data["yjit"]["available"]
        assert_equal "/does/not/exist/never_load_yjit", vm.autoload?(:YJIT)
      end
    end
  end

  def test_passenger_optional_and_no_hooks
    passenger = Module.new; passenger.const_set(:VERSION_STRING, "6.test")
    def passenger.on_event(*); raise "hook registered"; end
    with_constant(Object, :PhusionPassenger, passenger) do
      status, _, data = response
      assert_equal 200, status
      assert_equal "6.test", data["server"]["passenger_version"]
    end
  end

  def test_head_response_has_no_body
    status, headers, data, text = response(rack_env("", "REQUEST_METHOD" => "HEAD"))
    assert_equal 200, status
    assert_operator headers["content-length"].to_i, :>, 0
    assert_nil data
    assert_equal "", text
  end

  def test_other_http_methods
    %w[POST PUT PATCH DELETE OPTIONS].each do |method|
      status, _, data = response(rack_env("data", "REQUEST_METHOD" => method))
      assert_equal 200, status
      assert_equal method, data["request"]["metadata"]["REQUEST_METHOD"]
    end
  end

  def test_serialization_failure_uses_static_valid_fallback
    JSON.stub(:pretty_generate, proc { |*_| raise JSON::GeneratorError, "broken serializer" }) do
      status, headers, data, text = response
      assert_equal 500, status
      assert_equal RailsRuntimeInfo::Endpoint::FALLBACK_JSON, text
      assert data["error"]
      assert_equal text.bytesize.to_s, headers["content-length"]
    end
  end

  def test_fatal_exceptions_are_not_swallowed
    [NoMemoryError, SystemExit, Interrupt].each do |type|
      GC.stub(:stat, proc { raise type }) do
        assert_raises(type) { RailsRuntimeInfo::Endpoint.call(rack_env) }
      end
    end
  end

  def test_invalid_strings_and_cycles_in_rack_env
    env = rack_env("", "HTTP_X_BINARY" => "\xff".b)
    env["self"] = env
    status, _, data = response(env)
    assert_equal 200, status
    assert_equal "binary", data["request"]["headers"]["X-Binary"]["_type"]
    assert_equal "cycle", data["request"]["rack_environment"]["self"]["_type"]
  end
  def test_entire_collector_failure_does_not_fail_other_sections
    implementation = proc { raise "process assembly failed" }
    with_instance_method(RailsRuntimeInfo::Snapshot, :process_info, implementation) do
      status, _, data = response
      assert_equal 200, status
      assert_nil data["process"]
      assert_equal "RuntimeError", data["errors"]["process"]["class"]
      assert_equal "token=visible", data["request"]["metadata"]["QUERY_STRING"]
      assert data["gems"]
    end
  end

  def test_error_with_broken_message_does_not_break_error_reporting
    error_class = Class.new(StandardError) do
      def message; raise "message unavailable"; end
    end
    GC.stub(:stat, proc { raise error_class }) do
      status, _, data = response
      assert_equal 200, status
      assert_equal "(message unavailable)", data["errors"]["gc.stat"]["message"]
    end
  end

  def test_missing_lockfile_is_local_failure
    with_environment("BUNDLE_GEMFILE" => "/never/exists/Gemfile") do
      status, _, data = response
      assert_equal 200, status
      assert_nil data["gems"]["locked"]
      assert data["gems"]["activated"]
      assert_equal "Errno::ENOENT", data["errors"]["gems.locked"]["class"]
    end
  end

  def test_cached_bodies_do_not_bypass_capture_limit_through_rack_env
    limit = RailsRuntimeInfo::RequestInfo::BODY_LIMIT
    cached = "x" * (limit * 3)
    env = rack_env("unread input", "RAW_POST_DATA" => cached, "rack.request.form_vars" => cached, "rack.request.form_hash" => { "payload" => cached }, "action_dispatch.request.request_parameters" => { "payload" => cached }, "action_dispatch.request.parameters" => { "payload" => cached })
    # Even an indirect reference back to this env must not leak the cached body.
    env["nested"] = { "same_request" => env }
    status, _, data, text = response(env)
    assert_equal 200, status
    assert_equal limit, data["request"]["body"]["returned_bytes"]
    assert_equal "RAW_POST_DATA", data["request"]["body"]["source"]
    assert data["request"]["body"]["truncated"]
    assert_equal 0, env["rack.input"].pos
    refute_includes text, cached
    %w[RAW_POST_DATA rack.request.form_vars rack.request.form_hash action_dispatch.request.request_parameters action_dispatch.request.parameters].each do |key|
      assert_equal "request_body_cache", data["request"]["rack_environment"][key]["_type"]
    end
    assert_equal cached.bytesize, data["request"]["rack_environment"]["RAW_POST_DATA"]["bytesize"]
  end

end
