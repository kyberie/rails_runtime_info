# frozen_string_literal: true

require "test_helper"

class NonInvasiveTest < Minitest::Test
  def test_require_only_loads_own_ruby_files_and_preserves_global_state
    library = File.expand_path("../lib", __dir__)
    script = <<~RUBY
      before_env = ENV.to_h
      before_threads = Thread.list
      before_features = $LOADED_FEATURES.dup
      before_specs = Gem.loaded_specs.keys.sort
      before_path = $LOAD_PATH.dup
      require "rails_runtime_info"
      additions = $LOADED_FEATURES - before_features
      abort "external library loaded" unless additions.all? { |path| path.start_with?(#{library.inspect} + "/") }
      abort "environment changed" unless ENV.to_h == before_env
      abort "threads changed" unless Thread.list == before_threads
      abort "gems activated" unless Gem.loaded_specs.keys.sort == before_specs
      abort "load path changed" unless $LOAD_PATH == before_path
      abort "rails loaded" if defined?(Rails)
      puts "ok"
    RUBY
    output, error, status = Open3.capture3(RbConfig.ruby, "-I", library, "-e", script)
    assert status.success?, error + output
    assert_equal "ok\n", output
  end

  def test_no_database_bundler_or_service_access
    active_record = Module.new
    active_record.autoload(:Base, "/must/not/load/active_record")
    bundler = Module.new
    def bundler.load; raise "Bundler.load called"; end
    def bundler.definition; raise "Bundler.definition called"; end
    def bundler.setup; raise "Bundler.setup called"; end
    def bundler.settings; raise "Bundler.settings called"; end
    def bundler.default_lockfile; raise "Bundler.default_lockfile called"; end
    with_constant(Object, :ActiveRecord, active_record) do
      with_constant(Object, :Bundler, bundler) do
        status, _, data = response(what_env("+gems"))
        assert_equal 200, status
        assert data["gems"]
        assert_equal "/must/not/load/active_record", active_record.autoload?(:Base)
      end
    end
  end

  def test_endpoint_does_not_force_gc_or_change_gc_settings
    GC.stub(:start, proc { |*_| raise "forced GC" }) do
      GC.stub(:disable, proc { raise "GC disabled" }) do
        GC.stub(:enable, proc { raise "GC enabled" }) do
          status, _, _ = response
          assert_equal 200, status
        end
      end
    end
  end

  def test_no_request_or_snapshot_mutation
    env = rack_env("request body", "custom.array" => [1, 2], "custom.hash" => { "x" => 1 })
    before = env.dup
    before_env = ENV.to_h
    response(env)
    assert_equal before, env
    assert_equal [1, 2], env["custom.array"]
    assert_equal({ "x" => 1 }, env["custom.hash"])
    assert_equal before_env, ENV.to_h
    refute env["rack.input"].closed?
    # Reading the body necessarily advances this stream, and only this stream.
    assert_equal "request body".bytesize, env["rack.input"].pos
  end

  def test_response_body_retains_only_json_and_close_releases_it
    env = rack_env
    _, _, body = RailsRuntimeInfo::Endpoint.call(env)
    assert_equal [:@content], body.instance_variables
    assert_instance_of String, body.instance_variable_get(:@content)
    body.close
    assert_nil body.instance_variable_get(:@content)
    body.close
    chunks = []; body.each { |part| chunks << part }
    assert_equal [], chunks
    assert_equal [], RailsRuntimeInfo::Endpoint.instance_variables
  end

  def response_and_weak_reference
    env = rack_env("temporary")
    weak = WeakRef.new(env)
    [RailsRuntimeInfo::Endpoint.call(env), weak]
  end

  def test_response_does_not_retain_request_environment
    rack_response, weak = response_and_weak_reference
    # Forced GC is used in this TEST only, never in library code.
    3.times { GC.start }
    refute weak.weakref_alive?
    rack_response.last.close
  end

  def test_threads_do_not_share_request_state
    workers = 4.times.map do |index|
      Thread.new do
        _, _, data = response(rack_env("body-#{index}", "HTTP_X_REQUEST_MARKER" => index.to_s))
        [index, data["request"]["headers"]["X-Request-Marker"], data["request"]["body"]["data"]]
      end
    end
    workers.each do |thread|
      index, marker, body = thread.value
      assert_equal index.to_s, marker
      assert_equal "body-#{index}", body
    end
  end
end
