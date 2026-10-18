# frozen_string_literal: true

require "test_helper"

class PackageTest < Minitest::Test
  def specification
    Gem::Specification.load(File.expand_path("../rails_runtime_info.gemspec", __dir__))
  end

  def test_no_runtime_dependencies_and_ruby_24_target
    spec = specification
    assert_equal [], spec.runtime_dependencies
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("2.4.0"))
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("2.3.9"))
  end

  def test_documentation_and_implementation_are_packaged
    spec = specification
    %w[README.md AGENTS.md LICENSE lib/rails_runtime_info.rb docs/DESIGN.md].each do |file|
      assert_includes spec.files, file
    end
    refute spec.files.any? { |file| file.start_with?("/", "test/", ".git/") }
  end

  def test_gemspec_does_not_change_working_directory
    Dir.stub(:chdir, proc { |*_| raise "must not chdir" }) do
      assert specification
    end
  end
end
