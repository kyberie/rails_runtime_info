# frozen_string_literal: true

module RailsRuntimeInfo
  # Deliberately NOT a dependency resolver or Bundler::LockfileParser wrapper.
  # Read only the inventory portion of a lockfile, without evaluating Gemfile,
  # constructing Bundler source objects, or activating gems.
  class Lockfile
    LIMIT_BYTES = 4 * 1024 * 1024
    SOURCE_SECTIONS = ["GEM", "GIT", "PATH", "PLUGIN SOURCE"].freeze

    def self.path(root, environment)
      gemfile = environment["BUNDLE_GEMFILE"]
      if gemfile && !gemfile.empty?
        gemfile = File.expand_path(gemfile)
        return File.join(File.dirname(gemfile), "gems.locked") if File.basename(gemfile) == "gems.rb"
        return gemfile + ".lock"
      end
      directory = root || Dir.pwd
      # Bundler prefers gems.rb over Gemfile when both are present.
      if File.file?(File.join(directory, "gems.rb"))
        File.join(directory, "gems.locked")
      else
        File.join(directory, "Gemfile.lock")
      end
    end

    def self.read(path)
      new.parse(Support.read_file(path, LIMIT_BYTES)).merge("path" => path)
    end

    def parse(text)
      specs = []
      platforms = []
      bundled_with = nil
      ruby_version = nil
      source = nil
      section = nil
      in_specs = false
      recognized = false

      text.each_line do |line|
        line = line.chomp
        raise ArgumentError, "lockfile contains merge conflict markers" if line =~ /\A(?:<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)/
        if line =~ /\A\S/
          section = line
          source = SOURCE_SECTIONS.include?(section) ? section : nil
          in_specs = false
          recognized ||= !!source
        elsif source && line == "  specs:"
          in_specs = true
        elsif source && line =~ /\A  \S/
          in_specs = false
        elsif source && in_specs && line =~ /\A    (\S+) \(([^)]+)\)\s*\z/
          name, version_and_platform = Regexp.last_match.captures
          match = /\A([0-9][0-9A-Za-z.]*)(?:-(.+))?\z/.match(version_and_platform)
          specs << {
            "name" => name,
            "version" => match ? match[1] : nil,
            "platform" => match ? (match[2] || "ruby") : nil,
            "version_and_platform" => version_and_platform,
            "source_type" => source
          }
        elsif source && in_specs && line =~ /\A    \S/
          raise ArgumentError, "unrecognized locked gem entry"
        elsif section == "PLATFORMS" && line =~ /\A +\S/
          platforms << line.strip
        elsif section == "BUNDLED WITH" && line =~ /\A +\S/
          bundled_with = line.strip
        elsif section == "RUBY VERSION" && line =~ /\A +\S/
          ruby_version = line.strip
        end
      end
      raise ArgumentError, "no recognized gem source section in lockfile" unless recognized
      {
        "inventory" => "locked; may include inactive gems and other platforms",
        "gems" => specs.sort_by { |spec| [spec["name"], spec["version_and_platform"], spec["source_type"]] },
        "platforms" => platforms,
        "bundled_with" => bundled_with,
        "ruby_version" => ruby_version
      }
    end
  end
end
