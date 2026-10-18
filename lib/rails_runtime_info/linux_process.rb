# frozen_string_literal: true

module RailsRuntimeInfo
  class LinuxProcess
    SMALL_FILE_LIMIT = 64 * 1024
    MAPS_LIMIT = 2 * 1024 * 1024

    def self.read(path, limit = SMALL_FILE_LIMIT)
      Support.read_file(path, limit)
    end

    def self.fields(text)
      result = {}
      text.each_line do |line|
        match = /\A([A-Za-z_][A-Za-z0-9_]*):[ \t]*(.*?)\s*\z/.match(line)
        result[match[1]] = match[2] if match
      end
      result
    end

    def self.fd_count
      count = 0
      Dir.foreach("/proc/self/fd") { |name| count += 1 unless name == "." || name == ".." }
      count
    end

    def self.start_time
      # comm is parenthesized and may itself contain spaces and parentheses.
      text = read("/proc/self/stat")
      closing = text.rindex(")")
      raise ArgumentError, "unrecognized /proc/self/stat" unless closing
      fields = text[(closing + 1)..-1].split
      ticks = Integer(fields.fetch(19), 10) # field 22; state is field 3
      require "etc"
      ticks_per_second = Etc.sysconf(Etc::SC_CLK_TCK)
      raise ArgumentError, "invalid SC_CLK_TCK" unless ticks_per_second && ticks_per_second > 0
      uptime = Float(read("/proc/uptime").split.fetch(0))
      age = uptime - ticks.to_f / ticks_per_second
      {
        "start_ticks_since_boot" => ticks,
        "clock_ticks_per_second" => ticks_per_second,
        "age_seconds" => [age, 0.0].max,
        "started_at_utc_approximate" => Support.utc(Time.now - age)
      }
    end

    def self.allocator_hints
      # Mapped library names are evidence, not proof of the allocator actually
      # serving Ruby allocations. Static linkage will not appear here.
      read("/proc/self/maps", MAPS_LIMIT).each_line.select do |line|
        line =~ /(?:jemalloc|tcmalloc|mimalloc)/i
      end.map { |line| line.split(/\s+/, 6).last.to_s.strip }.uniq
    end
  end
end
