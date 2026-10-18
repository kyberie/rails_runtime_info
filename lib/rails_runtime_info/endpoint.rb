# frozen_string_literal: true

module RailsRuntimeInfo
  class Endpoint
    FALLBACK_JSON = "{\"error\":\"rails_runtime_info could not serialize the diagnostic response\"}\n".freeze

    def self.call(env)
      status = 200
      begin
        status, json = serialized_response(env)
      rescue StandardError, LoadError, NotImplementedError
        # Do not invoke application logging, exception formatting, or JSON again
        # on this last-resort path. Fatal exceptions deliberately propagate.
        status = 500
        json = FALLBACK_JSON
      end
      headers = {
        "content-type" => "application/json; charset=utf-8",
        "content-length" => json.bytesize.to_s,
        "cache-control" => "no-store",
        "x-content-type-options" => "nosniff"
      }
      # Keep HEAD valid even when invoked without Rack::Head middleware.
      head = env.kind_of?(Hash) && env["REQUEST_METHOD"] == "HEAD"
      [status, headers, Body.new(head ? nil : json)]
    end

    def self.serialized_response(env)
      require "json"
      begin
        document = Snapshot.new(env).document
        status = 200
      rescue Selection::Invalid => error
        # Parse selectors before collecting diagnostics or reading rack.input.
        # Keep this serialization inside call's last-resort failure boundary.
        status = 400
        document = {
          "error" => "invalid_what",
          "message" => error.message,
          "default_what" => Selection::DEFAULT,
          "categories" => Selection::CATEGORIES
        }
      end
      [status, JSON.pretty_generate(document) + "\n"]
    end
    private_class_method :serialized_response
  end
end
