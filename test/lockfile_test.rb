# frozen_string_literal: true

require "test_helper"

class LockfileTest < Minitest::Test
  LOCK = <<~LOCKFILE.freeze
    GIT
      remote: https://example.invalid/never-connect.git
      revision: abcdef
      specs:
        internal (1.2.3)
          rack (>= 2)

    PATH
      remote: ../local
      specs:
        local (0.1.0)

    GEM
      remote: https://rubygems.org/
      specs:
        nokogiri (1.18.10-x86_64-linux-gnu)
        nokogiri (1.18.10-arm64-darwin)
        rack (2.2.9)
        trial (1.0.0.pre.1)

    PLATFORMS
      ruby
      x86_64-linux

    DEPENDENCIES
      internal!
      nokogiri

    RUBY VERSION
       ruby 2.4.10p364

    BUNDLED WITH
       1.17.3
  LOCKFILE

  def test_reads_all_sources_platform_variants_and_versions
    output = RailsRuntimeInfo::Lockfile.new.parse(LOCK)
    assert_equal 6, output["gems"].size
    assert_equal ["GIT", "PATH", "GEM"].sort, output["gems"].map { |s| s["source_type"] }.uniq.sort
    native = output["gems"].select { |s| s["name"] == "nokogiri" }
    assert_equal ["1.18.10", "1.18.10"], native.map { |s| s["version"] }
    assert_equal ["arm64-darwin", "x86_64-linux-gnu"], native.map { |s| s["platform"] }
    assert_equal "1.17.3", output["bundled_with"]
    assert_equal "ruby 2.4.10p364", output["ruby_version"]
    assert_equal ["ruby", "x86_64-linux"], output["platforms"]
  end

  def test_crlf_and_unknown_future_sections
    text = LOCK + "\nFUTURE SECTION\n    future information\n"
    assert_equal 6, RailsRuntimeInfo::Lockfile.new.parse(text.gsub("\n", "\r\n"))["gems"].size
  end

  def test_plugin_source
    text = "PLUGIN SOURCE\n  remote: unused\n  specs:\n    plugin_gem (1.0)\n"
    assert_equal "plugin_gem", RailsRuntimeInfo::Lockfile.new.parse(text)["gems"].first["name"]
  end

  def test_malformed_entry_is_not_silently_omitted
    assert_raises(ArgumentError) { RailsRuntimeInfo::Lockfile.new.parse("GEM\n  specs:\n    bad!\n") }
  end

  def test_conflict_is_reported
    assert_raises(ArgumentError) { RailsRuntimeInfo::Lockfile.new.parse("<<<<<<< ours\n" + LOCK) }
  end

  def test_garbage_is_not_reported_as_empty_inventory
    assert_raises(ArgumentError) { RailsRuntimeInfo::Lockfile.new.parse("garbage\n") }
  end

  def test_bundle_gemfile_overrides_root_without_evaluation
    assert_equal "/tmp/custom.rb.lock", RailsRuntimeInfo::Lockfile.path("/unrelated", { "BUNDLE_GEMFILE" => "/tmp/custom.rb" })
    assert_equal "/tmp/gems.locked", RailsRuntimeInfo::Lockfile.path(nil, { "BUNDLE_GEMFILE" => "/tmp/gems.rb" })
  end

  def test_standard_root_and_gems_rb
    Dir.mktmpdir do |directory|
      assert_equal File.join(directory, "Gemfile.lock"), RailsRuntimeInfo::Lockfile.path(directory, {})
      File.write(File.join(directory, "gems.rb"), "raise 'must never evaluate'\n")
      assert_equal File.join(directory, "gems.locked"), RailsRuntimeInfo::Lockfile.path(directory, {})
    end
  end

  def test_file_read_is_bounded
    Dir.mktmpdir do |directory|
      path = File.join(directory, "lock")
      File.write(path, "abcde")
      assert_raises(RailsRuntimeInfo::Support::FileTooLarge) { RailsRuntimeInfo::Support.read_file(path, 4) }
      assert_equal "abcde", RailsRuntimeInfo::Support.read_file(path, 5)
    end
  end

  def test_non_regular_file_is_rejected
    assert_raises(RailsRuntimeInfo::Support::UnsupportedFile) { RailsRuntimeInfo::Support.read_file(Dir.tmpdir, 10) }
  end
end
