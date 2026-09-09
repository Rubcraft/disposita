# frozen_string_literal: true

require "rbconfig"

module Disposita
  # Cross-platform helpers for conventional configuration locations.
  #
  # Disposita owns only the mechanics of finding conventional user-level paths.
  # The consumer still owns application names, filenames and project-local path
  # conventions. In particular, Disposita never imposes a +.rubcraft+ or
  # +.disposita+ directory on project repositories.
  #
  # User paths follow platform conventions: XDG on Linux/Unix when available,
  # Application Support on macOS and APPDATA/LOCALAPPDATA on Windows.
  module Paths
    module_function

    # Returns the conventional per-user configuration directory for an app.
    #
    # Supplying +env+ and +host_os+ explicitly makes the method deterministic in
    # tests and lets embedding applications control which process environment
    # is observed.
    #
    # @param application [String, Symbol] application/domain directory name.
    # @param env [Hash] environment-like mapping used to find HOME/XDG/APPDATA.
    # @param host_os [String] operating-system identifier, usually Ruby's
    #   +RbConfig::CONFIG["host_os"]+.
    # @return [String] absolute or platform-native user configuration directory.
    # @raise [Disposita::PathError] if the application name is empty or no base
    #   user configuration directory can be determined.
    # @example
    #   Disposita::Paths.user_config("scm")
    #   # Linux:   ~/.config/scm
    #   # macOS:   ~/Library/Application Support/scm
    #   # Windows: %APPDATA%\\scm
    def user_config(application, env: ENV, host_os: RbConfig::CONFIG["host_os"])
      name = application.to_s
      raise PathError, "application name cannot be empty" if name.empty?

      base = config_home(env, host_os)

      raise PathError, "cannot determine user configuration directory" unless base

      ::File.join(base, name)
    end

    # Selects the platform base directory before appending a consumer name.
    # @api private
    # @param env [Hash] environment-like mapping.
    # @param host_os [String] platform identifier.
    # @return [String, nil] base directory when available.
    def config_home(env, host_os)
      return env["APPDATA"] || env["LOCALAPPDATA"] if windows?(host_os)
      return home_path(env, "Library", "Application Support") if macos?(host_os)

      env["XDG_CONFIG_HOME"] || home_path(env, ".config")
    end

    # Appends platform-specific directories to HOME when it is available.
    # @api private
    # @param env [Hash] environment-like mapping.
    # @param segments [Array<String>] directory names.
    # @return [String, nil] path under HOME.
    def home_path(env, *segments)
      ::File.join(env["HOME"], *segments) if env["HOME"]
    end
    private_class_method :config_home, :home_path

    # Resolves a consumer-selected path inside a project root.
    #
    # The method protects against +..+ traversal escaping the supplied root. It
    # does not choose the relative filename or directory; that policy belongs to
    # the application using Disposita.
    #
    # @param root [String] project root.
    # @param relative [String] relative path chosen by the consumer.
    # @return [String] expanded path contained by +root+.
    # @raise [Disposita::PathError] when the resolved path escapes +root+.
    # @example
    #   Disposita::Paths.project(Dir.pwd, ".rubcraft/scm.yml")
    def project(root, relative)
      root = ::File.expand_path(root)
      candidate = ::File.expand_path(relative, root)
      unless candidate == root || candidate.start_with?("#{root}#{::File::SEPARATOR}")
        raise PathError, "project configuration path escapes project root"
      end

      candidate
    end

    # @param host_os [String] Ruby host OS identifier.
    # @return [Boolean] whether the identifier represents Windows.
    def windows?(host_os) = host_os.match?(/mswin|mingw|cygwin/i)

    # @param host_os [String] Ruby host OS identifier.
    # @return [Boolean] whether the identifier represents macOS.
    def macos?(host_os) = host_os.match?(/darwin/i)
  end
end
