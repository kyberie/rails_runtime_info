# frozen_string_literal: true

module RailsRuntimeInfo
  # Holds only the final JSON, never the request or intermediate snapshot.
  # Rack servers/middleware must close response bodies; release our reference
  # even if the enclosing response object happens to remain reachable.
  class Body
    def initialize(content)
      @content = content
    end

    def each
      yield @content unless @content.nil?
    end

    def close
      @content = nil
    end
  end
end
