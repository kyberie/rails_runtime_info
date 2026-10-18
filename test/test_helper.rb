# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "stringio"
require "uri"
require "tmpdir"
require "open3"
require "rbconfig"
require "weakref"
require "rails_runtime_info"

module TestHelpers
  def rack_env(body = "", overrides = {})
    {
      "REQUEST_METHOD" => "GET", "SCRIPT_NAME" => "", "PATH_INFO" => "/_internal/diagnostics",
      "QUERY_STRING" => "token=visible", "SERVER_NAME" => "app.internal", "SERVER_PORT" => "443",
      "SERVER_PROTOCOL" => "HTTP/1.1", "rack.url_scheme" => "https", "rack.input" => StringIO.new(body),
      "rack.errors" => StringIO.new, "rack.version" => [1, 3], "rack.multithread" => false,
      "rack.multiprocess" => true, "rack.run_once" => false, "HTTP_HOST" => "app.internal"
    }.merge(overrides)
  end

  def what_env(expression, body = "", overrides = {})
    rack_env(body, { "QUERY_STRING" => URI.encode_www_form("what" => expression) }.merge(overrides))
  end

  def response(env = rack_env)
    status, headers, body = RailsRuntimeInfo::Endpoint.call(env)
    text = String.new
    begin
      body.each { |chunk| text << chunk }
    ensure
      body.close
    end
    [status, headers, text.empty? ? nil : JSON.parse(text), text]
  end

  def with_environment(changes)
    previous = {}
    changes.each do |key, value|
      previous[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def with_constant(parent, name, replacement)
    existed = parent.const_defined?(name, false)
    autoload_path = parent.autoload?(name)
    old = parent.const_get(name, false) if existed && !autoload_path
    parent.send(:remove_const, name) if existed
    parent.const_set(name, replacement)
    yield
  ensure
    parent.send(:remove_const, name) if parent.const_defined?(name, false)
    if autoload_path
      parent.autoload(name, autoload_path)
    elsif existed
      parent.const_set(name, old)
    end
  end

  def with_instance_method(klass, method, implementation)
    original = klass.instance_method(method)
    was_private = klass.private_method_defined?(method)
    klass.send(:define_method, method, &implementation)
    yield
  ensure
    klass.send(:define_method, method, original)
    klass.send(:private, method) if was_private
  end
end

class Minitest::Test
  include TestHelpers
end
