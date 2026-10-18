# frozen_string_literal: true

module RailsRuntimeInfo
  class Snapshot
    CONFIG_FIELDS = %w[eager_load cache_classes enable_reloading time_zone force_ssl log_level].freeze
    DEPLOYMENT_KEYS = %w[APP_NAME APP_VERSION APP_REVISION APP_BUILD_TIME RELEASE_VERSION RELEASE_SHA GIT_COMMIT SOURCE_VERSION].freeze

    def initialize(env)
      @env = env
      @errors = {}
      @selection = Selection.new(env["QUERY_STRING"])
    end

    def document
      data = { "gem_version" => VERSION, "time_utc" => Support.utc(Time.now) }
      # Sample GC/JIT before allocating the bulk of the diagnostic document.
      section(data, "gc") { collect_gc }
      section(data, "yjit") { collect_yjit }
      capture(data, "runtime") { runtime }
      section(data, "application") { application }
      section(data, "process") { process_info }
      section(data, "server") { server_info }
      section(data, "gems") { gem_info }
      capture(data, "environment") { ENV.to_h }
      capture(data, "loaded_features") { $LOADED_FEATURES.dup }
      capture(data, "load_path") { $LOAD_PATH.dup }
      section(data, "request") { request_info }
      data["errors"] = @errors
      @selection.filter!(data)
      # Collection order and display order are separate: sample GC/YJIT early,
      # yet keep the most useful human-facing sections at the end of the JSON.
      Selection::CATEGORIES.each_with_object({}) do |key, ordered|
        ordered[key] = data[key] if data.key?(key)
      end
    end

    private

    # Each independent field has an exception boundary. Normalization is inside
    # that boundary too; no raw exception or request objects escape into JSON.
    def capture(target, key, error_key = key, normalizer_options = {})
      return unless @selection.requested?(error_key)
      target[key] = Normalizer.new(normalizer_options).call(yield)
    rescue StandardError, LoadError, NotImplementedError => error
      target[key] = nil
      @errors[error_key] = error_description(error)
      nil
    end

    # Sections already contain normalized fields. Guard their assembly without
    # making a second deep copy of potentially large snapshots.
    def section(target, key)
      return unless @selection.requested?(key)
      target[key] = yield
    rescue StandardError, LoadError, NotImplementedError => error
      target[key] = nil
      @errors[key] = error_description(error)
    end

    def error_description(error)
      message = begin
        Normalizer.new.call(error.message)
      rescue StandardError, LoadError, NotImplementedError
        "(message unavailable)"
      end
      { "class" => Support.class_name(error), "message" => message }
    end

    def loaded(parent, name)
      Support.loaded_constant(parent, name)
    end

    def collect_gc
      result = {}
      [:stat, :latest_gc_info, :stat_heap].each do |method|
        next unless GC.respond_to?(method)
        capture(result, method.to_s, "gc.#{method}") { GC.public_send(method) }
      end
      result
    end

    def collect_yjit
      result = {}
      vm = loaded(Object, :RubyVM)
      yjit = vm && loaded(vm, :YJIT)
      capture(result, "available", "yjit.available") { !!yjit }
      if yjit
        { "enabled" => :enabled?, "stats_enabled" => :stats_enabled?, "runtime_stats" => :runtime_stats }.each do |key, method|
          next unless yjit.respond_to?(method)
          capture(result, key, "yjit.#{key}") { yjit.public_send(method) }
        end
      end
      result
    end

    def runtime
      require "rbconfig"
      {
        "ruby_description" => RUBY_DESCRIPTION,
        "ruby_version" => RUBY_VERSION,
        "ruby_engine" => defined?(RUBY_ENGINE) ? RUBY_ENGINE : "ruby",
        "ruby_engine_version" => defined?(RUBY_ENGINE_VERSION) ? RUBY_ENGINE_VERSION : nil,
        "ruby_platform" => RUBY_PLATFORM,
        "ruby_executable" => RbConfig.ruby,
        "ruby_build" => {
          "arch" => RbConfig::CONFIG["arch"],
          "host" => RbConfig::CONFIG["host"],
          "configure_args" => RbConfig::CONFIG["configure_args"]
        },
        "versions" => library_versions
      }
    end

    def library_versions
      versions = {}
      gem_module = loaded(Object, :Gem)
      versions["rubygems"] = loaded(gem_module, :VERSION) if gem_module
      bundler = loaded(Object, :Bundler)
      versions["bundler"] = loaded(bundler, :VERSION) if bundler
      if gem_module && gem_module.respond_to?(:loaded_specs)
        %w[rails railties rack bundler json passenger puma].each do |name|
          spec = gem_module.loaded_specs[name]
          versions[name] = spec.version.to_s if spec
        end
      end
      versions
    end

    def application
      result = {}
      rails = loaded(Object, :Rails)
      result["rails_loaded"] = !!rails
      capture(result, "deployment", "application.deployment") do
        DEPLOYMENT_KEYS.each_with_object({}) { |key, out| out[key] = ENV[key] if ENV.key?(key) }
      end
      return result unless rails
      capture(result, "environment", "application.environment") do
        value = rails.instance_variable_get(:@_env)
        value.kind_of?(String) ? String.new(value) : nil
      end
      # Rails.application can instantiate an application. Only inspect an
      # already-created application and already-created configuration instead.
      app = rails.instance_variable_get(:@application)
      result["application_instantiated"] = !!app
      return result unless app
      result["class"] = Support.class_name(app)
      capture(result, "initialized", "application.initialized") { app.instance_variable_get(:@initialized) }
      config = app.instance_variable_get(:@config)
      result["configuration_instantiated"] = !!config
      return result unless config
      capture(result, "root", "application.root") do
        value = config.root
        if value.kind_of?(String)
          String.new(value)
        elsif Support.class_name(value) == "Pathname"
          value.to_s
        end
      end
      CONFIG_FIELDS.each do |key|
        next unless config.respond_to?(key)
        capture(result, key, "application.#{key}") { config.public_send(key) }
      end
      capture(result, "cache_backend_class", "application.cache_backend_class") do
        cache = rails.instance_variable_get(:@cache)
        cache ? Support.class_name(cache) : nil
      end
      # Read configuration only, never ActiveJob::Base.queue_adapter (which
      # could autoload and instantiate an adapter).
      if config.respond_to?(:active_job)
        capture(result, "configured_job_adapter", "application.configured_job_adapter") do
          options = config.active_job
          options.respond_to?(:queue_adapter) ? options.queue_adapter : nil
        end
      end
      result
    rescue StandardError, LoadError, NotImplementedError => error
      @errors["application"] = error_description(error)
      result
    end

    def process_info
      result = {}
      [:pid, :ppid, :uid, :euid, :gid, :egid, :groups].each do |method|
        capture(result, method.to_s, "process.#{method}") { Process.public_send(method) }
      end
      capture(result, "ruby_threads", "process.ruby_threads") { Thread.list.size }
      capture(result, "cpu_seconds", "process.cpu_seconds") do
        times = Process.times
        { "user" => times.utime, "system" => times.stime, "children_user" => times.cutime, "children_system" => times.cstime }
      end
      capture(result, "working_directory", "process.working_directory") { Dir.pwd }
      capture(result, "program_name", "process.program_name") { $0 }
      capture(result, "argv", "process.argv") { ARGV.dup }
      capture(result, "uname", "process.uname") { require "etc"; Etc.uname }
      if @selection.requested?("process.linux")
        result["linux"] = RUBY_PLATFORM.include?("linux") ? linux_info : { "available" => false }
      end
      result
    end

    def linux_info
      result = { "available" => true }
      {
        "status" => "/proc/self/status",
        "smaps_rollup" => "/proc/self/smaps_rollup",
        "io" => "/proc/self/io"
      }.each do |key, path|
        capture(result, key, "process.linux.#{key}") { LinuxProcess.fields(LinuxProcess.read(path)) }
      end
      {
        "limits" => "/proc/self/limits",
        "cgroup" => "/proc/self/cgroup",
        "os_release" => "/etc/os-release"
      }.each do |key, path|
        capture(result, key, "process.linux.#{key}") { LinuxProcess.read(path) }
      end
      capture(result, "command_line", "process.linux.command_line") { LinuxProcess.read("/proc/self/cmdline").split("\0") }
      capture(result, "executable", "process.linux.executable") { File.readlink("/proc/self/exe") }
      capture(result, "open_fds", "process.linux.open_fds") { LinuxProcess.fd_count }
      capture(result, "lifetime", "process.linux.lifetime") { LinuxProcess.start_time }
      capture(result, "allocator_library_hints", "process.linux.allocator_library_hints") { LinuxProcess.allocator_hints }
      result
    end

    def server_info
      result = { "software" => @env["SERVER_SOFTWARE"] }
      passenger = loaded(Object, :PhusionPassenger)
      result["passenger_constant_loaded"] = !!passenger
      if passenger
        capture(result, "passenger_version", "server.passenger_version") { loaded(passenger, :VERSION_STRING) }
      end
      Normalizer.new.call(result)
    end

    def gem_info
      result = {}
      capture(result, "activated", "gems.activated") do
        gem_module = loaded(Object, :Gem)
        if gem_module && gem_module.respond_to?(:loaded_specs)
          gem_module.loaded_specs.values.dup.map do |spec|
            { "name" => spec.name, "version" => spec.version.to_s, "platform" => spec.platform.to_s }
          end.sort_by { |spec| [spec["name"], spec["version"], spec["platform"]] }
        end
      end
      result
    end

    def request_info
      result = {}
      request = RequestInfo.new(@env)
      capture(result, "metadata", "request.metadata") { request.metadata }
      capture(result, "headers", "request.headers") { request.headers }
      capture(result, "reconstructed_url", "request.reconstructed_url") { request.reconstructed_url }
      capture(result, "rack_environment", "request.rack_environment", :request_environment => true) { @env }
      capture(result, "body", "request.body") { request.body }
      result
    end
  end
end
