# frozen_string_literal: true

module RailsRuntimeInfo
  module Support
    class FileTooLarge < StandardError; end
    class UnsupportedFile < StandardError; end

    # Do not resolve autoloads merely to find out whether a framework exists.
    def self.loaded_constant(parent, name)
      return nil unless parent.kind_of?(Module)
      return nil if parent.autoload?(name)
      return nil unless parent.const_defined?(name, false)
      parent.const_get(name, false)
    end

    def self.class_name(object)
      klass = Object.instance_method(:class).bind(object).call
      Module.instance_method(:name).bind(klass).call || "(anonymous class)"
    rescue StandardError
      "(unknown class)"
    end

    def self.utc(time)
      time.getutc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ")
    end

    # Bounded reads of known local files. NONBLOCK prevents a misconfigured
    # lockfile FIFO from hanging on open; fstat rejects non-regular files.
    # This is not a timeout for slow filesystems or /proc generation.
    def self.read_file(path, limit)
      flags = File::RDONLY
      flags |= File::NONBLOCK if File.const_defined?(:NONBLOCK)
      File.open(path, flags) do |io|
        raise UnsupportedFile, "not a regular file: #{path}" unless io.stat.file?
        io.binmode
        data = io.read(limit + 1) || ""
        raise FileTooLarge, "file exceeds #{limit} bytes: #{path}" if data.bytesize > limit
        data
      end
    end
  end
end
