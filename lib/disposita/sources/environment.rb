# frozen_string_literal: true

module Disposita
  module Sources
    # Read-only source that maps environment variables to declared settings.
    #
    # Per-setting +env:+ names take precedence. When a prefix is supplied,
    # settings without an explicit name derive one from their full schema path;
    # for example +server.port+ with prefix +MY_APP+ becomes
    # +MY_APP_SERVER_PORT+.
    #
    # Environment values remain raw strings here. Type coercion belongs to the
    # Schema so every source follows the same validation rules.
    #
    # @example
    #   source = Disposita::Sources::Environment.new(
    #     env: { "APP_SERVER_PORT" => "9292" },
    #     prefix: "APP"
    #   )
    #   schema.resolve([source]).server.port # => 9292
    class Environment < Source
      # @param env [Hash] environment-like mapping; defaults to the process ENV.
      #   Pass a Hash to isolate resolution from the process environment.
      # @param prefix [String, nil] optional generated-variable prefix.
      # @param name [String, Symbol] provenance name.
      def initialize(env: ENV, prefix: nil, name: :environment)
        super(name: name)
        @env = env
        @prefix = prefix
      end

      # Builds a partial configuration layer from variables present in +env+.
      #
      # @param schema [Disposita::Schema] schema whose setting metadata is used
      #   to determine variable names.
      # @return [Hash] nested raw configuration values.
      def read(schema)
        schema.settings.each_with_object({}) do |setting, data|
          env_name = setting.env || generated_name(setting)
          next unless env_name && @env.key?(env_name)

          Internal::HashTools.set(data, setting.path, @env.fetch(env_name))
        end
      end

      private

      def generated_name(setting)
        return unless @prefix

        ([@prefix] + setting.path).join("_").upcase
      end
    end
  end
end
