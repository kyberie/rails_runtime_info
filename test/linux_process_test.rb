# frozen_string_literal: true

require "test_helper"

class LinuxProcessTest < Minitest::Test
  def test_proc_fields_keep_units_and_all_keys
    assert_equal({ "VmRSS" => "123 kB", "Future" => "abc: def" }, RailsRuntimeInfo::LinuxProcess.fields("VmRSS:\t123 kB\nFuture: abc: def\n"))
  end

  def test_current_process_lifetime
    skip "Linux only" unless RUBY_PLATFORM.include?("linux") && File.file?("/proc/self/stat")
    result = RailsRuntimeInfo::LinuxProcess.start_time
    assert_operator result["clock_ticks_per_second"], :>, 0
    assert_operator result["age_seconds"], :>=, 0
    assert_match(/Z\z/, result["started_at_utc_approximate"])
  end

  def test_stat_command_name_can_contain_parentheses_and_spaces
    fields = ["S"] + Array.new(18, "0") + ["250"] + ["0", "0"]
    stat = "1 (name with ) and ( brackets) " + fields.join(" ")
    reader = proc do |path, *|
      path == "/proc/self/stat" ? stat : "10.0 1.0\n"
    end
    RailsRuntimeInfo::LinuxProcess.stub(:read, reader) do
      result = RailsRuntimeInfo::LinuxProcess.start_time
      assert_equal 250, result["start_ticks_since_boot"]
    end
  end

  def test_fd_count
    skip "Linux only" unless File.directory?("/proc/self/fd")
    assert_operator RailsRuntimeInfo::LinuxProcess.fd_count, :>, 0
  end

  def test_allocator_hints_are_not_claimed_as_allocator_identity
    maps = "7f-8f r-xp 0 00:00 1 /usr/lib/libjemalloc.so.2\n8f-9f r--p 0 00:00 1 /usr/lib/libjemalloc.so.2\n9f-af r-xp 0 00:00 2 /usr/lib/libc.so.6\n"
    RailsRuntimeInfo::LinuxProcess.stub(:read, maps) do
      assert_equal ["/usr/lib/libjemalloc.so.2"], RailsRuntimeInfo::LinuxProcess.allocator_hints
    end
  end
  def test_smaps_mapping_header_is_not_mistaken_for_a_counter
    text = "1234-5678 ---p 00000000 00:00 0 [rollup]\nPss: 12 kB\n"
    assert_equal({ "Pss" => "12 kB" }, RailsRuntimeInfo::LinuxProcess.fields(text))
  end

end
