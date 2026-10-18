# frozen_string_literal: true

require "test_helper"

class RequestSecurityTest < Minitest::Test
  SECRET_KEYS = %w[action_dispatch.secret_key_base action_dispatch.secret_token action_dispatch.key_generator action_dispatch.cookies_rotations action_dispatch.future_secret].freeze

  def test_only_allowlisted_action_dispatch_keys_survive
    env = what_env("-all,+request.rack_environment")
    safe = {
      "action_dispatch.request_id" => "trace-123",
      "action_dispatch.remote_ip" => "192.0.2.1",
      "action_dispatch.original_path" => "/original",
      "action_dispatch.request.path_parameters" => { :controller => "example", :action => "show" },
      "action_dispatch.show_exceptions" => true,
      "action_dispatch.show_detailed_exceptions" => false
    }
    safe.each { |key, value| env[key] = value }
    SECRET_KEYS.each { |key| env[key] = "SERVER_ONLY_#{key}" }
    env["action_dispatch.signed_cookie_salt"] = "SERVER_ONLY_salt"
    env["action_dispatch.cookies_serializer"] = "SERVER_ONLY_config"
    env["action_dispatch.request.query_parameters"] = { "internal" => "SERVER_ONLY_parameters" }
    _, _, data, text = response(env)
    returned = data["request"]["rack_environment"]
    assert_equal safe.keys.sort, returned.keys.grep(/\Aaction_dispatch\./).sort
    assert_equal "trace-123", returned["action_dispatch.request_id"]
    assert_equal({ "controller" => "example", "action" => "show" }, returned["action_dispatch.request.path_parameters"])
    refute_includes text, "SERVER_ONLY_"
    SECRET_KEYS.each { |key| assert_equal "SERVER_ONLY_#{key}", env[key] }
  end

  def test_all_selector_does_not_disable_security_omissions
    env = what_env("+all", "", "action_dispatch.secret_key_base" => "SERVER_ONLY_base", "action_dispatch.secret_token" => "SERVER_ONLY_token")
    _, _, data, text = response(env)
    refute data["request"]["rack_environment"].key?("action_dispatch.secret_key_base")
    refute data["request"]["rack_environment"].key?("action_dispatch.secret_token")
    refute_includes text, "SERVER_ONLY_"
  end

  def test_explicit_inclusion_cannot_enable_forbidden_key
    env = what_env("-all,+request.rack_environment.action_dispatch.secret_key_base", "", "action_dispatch.secret_key_base" => "SERVER_ONLY_base")
    _, _, data, text = response(env)
    assert_equal({}, data)
    refute_includes text, "SERVER_ONLY_base"
  end

  def test_rotation_hashes_and_arrays_are_never_serialized
    env = rack_env("", "action_dispatch.cookies_rotations" => { "signed" => [["SERVER_ONLY_old_signing_key"]], "encrypted" => [["SERVER_ONLY_encryption_key"]] }, "action_dispatch.key_generator" => { "secret" => "SERVER_ONLY_generator_key" })
    _, _, data, text = response(env)
    refute data["request"]["rack_environment"].key?("action_dispatch.cookies_rotations")
    refute data["request"]["rack_environment"].key?("action_dispatch.key_generator")
    refute_includes text, "SERVER_ONLY_"
  end

  def test_recursive_env_aliases_and_symbol_keys_do_not_bypass_omissions
    nested = {
      :"action_dispatch.secret_key_base" => "SERVER_ONLY_nested",
      :"action_dispatch.request_id" => "nested-id",
      "action_dispatch" => { "secret_key_base" => "SERVER_ONLY_container" }
    }
    env = rack_env("", "custom.nested" => nested, "action_dispatch.secret_key_base" => "SERVER_ONLY_top")
    env["self"] = env
    _, _, data, text = response(env)
    assert_equal({ "action_dispatch.request_id" => "nested-id" }, data["request"]["rack_environment"]["custom.nested"])
    assert_equal "cycle", data["request"]["rack_environment"]["self"]["_type"]
    refute_includes text, "SERVER_ONLY_"
    assert nested.key?(:"action_dispatch.secret_key_base")
  end

  def test_rack_session_options_are_omitted_even_outside_rails_namespace
    env = rack_env("", "rack.session.options" => { :secret => "SERVER_ONLY_session_secret", :old_secret => "SERVER_ONLY_previous_secret", :key => "session" })
    _, _, data, text = response(env)
    refute data["request"]["rack_environment"].key?("rack.session.options")
    refute_includes text, "SERVER_ONLY_"
    assert env["rack.session.options"].key?(:secret)
  end

  def test_http_credentials_are_not_mistaken_for_rails_server_config
    env = what_env("request.body", "request-secret", "HTTP_AUTHORIZATION" => "Basic client-auth", "HTTP_COOKIE" => "client-cookie", "HTTP_ACTION_DISPATCH_SECRET_KEY_BASE" => "client-provided-header")
    _, _, data = response(env)
    assert_equal "Basic client-auth", data["request"]["headers"]["Authorization"]
    assert_equal "client-cookie", data["request"]["headers"]["Cookie"]
    assert_equal "client-provided-header", data["request"]["headers"]["Action-Dispatch-Secret-Key-Base"]
    assert_equal "client-provided-header", data["request"]["rack_environment"]["HTTP_ACTION_DISPATCH_SECRET_KEY_BASE"]
    assert_equal "request-secret", data["request"]["body"]["data"]
  end

  def test_security_omissions_are_scoped_to_rack_environment_not_user_env
    value = { "action_dispatch.secret_key_base" => "synthetic-explicit-input" }
    normalized = RailsRuntimeInfo::Normalizer.new.call(value)
    assert_equal value, normalized
  end
end
