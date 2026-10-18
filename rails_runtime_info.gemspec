# frozen_string_literal: true

require_relative "lib/rails_runtime_info/version"

Gem::Specification.new do |spec|
  spec.name = "rails_runtime_info"
  spec.version = RailsRuntimeInfo::VERSION
  spec.authors = ["Jan Seda"]
  spec.email = ["git.codex.91ndg9n33q@hodor.cz"]
  spec.summary = "Non-invasive, on-demand runtime diagnostics for Rails and Rack"
  spec.description = "A read-only, best-effort JSON snapshot of a Rails/Rack request, environment, gems, GC, YJIT, and process. No hooks, middleware, database connections, or runtime gem dependencies."
  spec.license = "Nonstandard"
  spec.required_ruby_version = ">= 2.4"
  root = File.expand_path(__dir__)
  patterns = ["lib/**/*.rb", "README.md", "AGENTS.md", "LICENSE", "CHANGELOG.md", "docs/**/*.md"]
  spec.files = patterns.flat_map { |pattern| Dir[File.join(root, pattern)] }.map { |path| path[(root.length + 1)..-1] }.sort
  spec.require_paths = ["lib"]
  # Private by default. Deliberately do not grant publishing permission here.
  spec.metadata["allowed_push_host"] = "https://private.invalid"
end
