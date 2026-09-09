# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Disposita
  # Built-in layers for files, environment variables and in-memory values.
  # Pass sources to Schema#resolve in highest-to-lowest order of precedence.
  module Sources
    # File-backed configuration source with atomic persistence.
    #
    # YAML is the default format, but any codec implementing +load(String)+ and
    # +dump(Hash)+ can be supplied. Missing files behave as empty layers, which
    # makes optional global/project configuration straightforward.
    #
    # Secret persistence is denied by default because project configuration is
    # frequently committed to source control. A caller may explicitly opt in
    # with +allow_secrets: true+ for a trusted local target; such files are
    # written with mode +0600+ where supported. This is a persistence policy,
    # not encryption.
    #
    # Writes use a temporary file in the destination directory and rename it
    # into place after flushing and fsyncing, reducing the chance of partially
    # written configuration.
    #
    # @example Read and write a project file
    #   schema = Disposita.define_schema(:app) do
    #     namespace(:server) { setting :port, type: Integer, default: 3000 }
    #   end
    #   source = Disposita::Sources::File.new(".app.yml", name: :project)
    #   config = schema.resolve(sources: [source])
    #   schema.write(source, server: { port: 9292 })
    class File < Source
      # @return [String] expanded backing file path.
      attr_reader :path

      # @param path [String] configuration file path.
      # @param name [String, Symbol] provenance name.
      # @param format [Object] codec implementing +load+ and +dump+.
      # @param allow_secrets [Boolean] whether secret settings may be written.
      def initialize(path, name: :file, format: Formats::YAML, allow_secrets: false)
        super(name: name)
        @path = ::File.expand_path(path)
        @format = format
        @allow_secrets = allow_secrets
      end

      # Reads and decodes the file.
      #
      # @param _schema [Disposita::Schema] unused by the built-in file source.
      # @return [Hash] normalized partial configuration; empty if file is absent.
      # @raise [Disposita::ParseError] when the configured codec rejects content.
      # @raise [Disposita::LoadError] when the file cannot be read.
      def read(_schema)
        return {} unless ::File.exist?(path)

        Internal::HashTools.symbolize(@format.load(::File.read(path)))
      rescue ParseError
        raise
      rescue SystemCallError => e
        raise LoadError, "cannot read #{path}: #{e.message}"
      end

      # @return [Boolean] always +true+ for a File source.
      def writable? = true

      # @return [Boolean] whether secret settings were explicitly allowed.
      def allows_secret_persistence? = @allow_secrets

      # Atomically persists validated configuration data.
      #
      # Prefer calling {Disposita::Schema#write}; it validates types, unknown
      # keys and schema version before delegating here.
      #
      # @param schema [Disposita::Schema] schema used to identify secret fields.
      # @param data [Hash] validated payload.
      # @return [String] backing file path.
      # @raise [Disposita::UnsafeSecretPersistenceError] when secret data is
      #   present and +allow_secrets+ is false.
      # @raise [Disposita::SaveError] when filesystem persistence fails.
      def write(schema, data)
        reject_secrets!(schema, data) unless allows_secret_persistence?
        replace_file(@format.dump(data))
        path
      rescue UnsafeSecretPersistenceError
        raise
      rescue SystemCallError => e
        raise SaveError, "cannot write #{path}: #{e.message}"
      end

      private

      def replace_file(content)
        directory = ::File.dirname(path)
        FileUtils.mkdir_p(directory)
        Tempfile.create([".disposita", ".tmp"], directory) do |temporary|
          temporary.write(content)
          temporary.flush
          temporary.fsync
          ::File.chmod(0o600, temporary.path) if allows_secret_persistence?
          ::File.rename(temporary.path, path)
        end
      end

      def reject_secrets!(schema, data)
        schema.each_setting.select { |item| item[:secret] }.each do |setting|
          if Internal::HashTools.get(data, setting[:path].split(".").map(&:to_sym)).equal?(Internal::UNDEFINED)
            next
          end

          raise UnsafeSecretPersistenceError,
                "refusing to persist secret setting #{setting[:path].inspect} to #{path}"
        end
      end
    end
  end
end
