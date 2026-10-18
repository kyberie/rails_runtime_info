# frozen_string_literal: true

# Requiring the gem defines its implementation only. Do not add boot-time
# collectors, Rails integration, framework requires, or mutable global state.
require_relative "rails_runtime_info/version"
require_relative "rails_runtime_info/support"
require_relative "rails_runtime_info/normalizer"
require_relative "rails_runtime_info/body"
require_relative "rails_runtime_info/selection"
require_relative "rails_runtime_info/request_info"
require_relative "rails_runtime_info/linux_process"
require_relative "rails_runtime_info/snapshot"
require_relative "rails_runtime_info/endpoint"
