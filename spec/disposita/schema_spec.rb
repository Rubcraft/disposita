# frozen_string_literal: true

# Contracts for schema declaration, layering, validation and persistence.
#
# This file exercises Disposita's central public behavior: nested settings,
# defaults, coercion, ordered source precedence, provenance, environment/runtime
# overrides, schema versions, custom validation and explicit writes.

RSpec.describe Disposita::Schema do
  subject(:schema) do
    Disposita.define_schema(:scm, version: 2) do
      namespace :git do
        setting :remote, type: String, default: "origin"
        setting :port, type: Integer, required: true
        setting :transport, type: Disposita::Types.enum(:ssh, :https), default: :ssh
        setting :enabled, type: Disposita::Types.boolean, default: true
        setting :token, type: String, optional: true, secret: true, env: "SCM_TOKEN"
        setting :retries, type: Integer, default: 3 do |value|
          value >= 0
        end
      end
    end
  end

  describe "schema definition" do
    it "describes nested settings" do
      expect(schema.describe("git.transport")).to include(
        path: "git.transport",
        default: :ssh,
        has_default: true,
        secret: false
      )
    end

    it "rejects duplicate settings" do
      expect do
        Disposita.define_schema(:bad) do
          setting :name, type: String
          setting :name, type: String
        end
      end.to raise_error(Disposita::SchemaError, /duplicate setting/)
    end

    it "allows defaults to satisfy required settings" do
      required = Disposita.define_schema(:app) do
        setting :name, type: String, required: true, default: "x"
      end
      expect(required.resolve.name).to eq("x")
      expect(required.resolve.source_of(:name)).to eq(:default)
    end
  end

  describe "resolution" do
    it "merges defaults and ordered layers" do
      global = Disposita::Sources::Memory.new({ git: { port: "22", transport: "https" } }, name: :global)
      project = Disposita::Sources::Memory.new({ git: { port: "2222" } }, name: :project)

      config = schema.resolve(sources: [project, global])

      expect(config.git.to_h).to include(remote: "origin", transport: :https, port: 2222)
      expect(config.source_of("git.transport")).to eq(:global)
      expect(config.source_of("git.port")).to eq(:project)
    end

    it "replaces arrays rather than concatenating them" do
      array_schema = Disposita.define_schema(:array) do
        setting :items, type: Disposita::Types.array(String), default: %w[a b]
      end

      config = array_schema.resolve(sources: [Disposita::Sources::Memory.new({ items: ["c"] })])

      expect(config.items).to eq(["c"])
    end

    it "raises when a required setting remains absent" do
      expect { schema.resolve }.to raise_error(Disposita::MissingSettingError, /git.port/)
    end

    it "rejects unknown settings" do
      source = Disposita::Sources::Memory.new({ git: { porrt: 22, port: 22 } })

      expect { schema.resolve(sources: [source]) }.to raise_error(Disposita::UnknownSettingError, /git.porrt/)
    end

    it "rejects values that fail custom validation" do
      source = Disposita::Sources::Memory.new({ git: { port: 22, retries: -1 } })

      expect { schema.resolve(sources: [source]) }.to raise_error(Disposita::ValidationError, /git.retries/)
    end

    it "rejects a newer persisted schema version" do
      source = Disposita::Sources::Memory.new({ version: 99, git: { port: 22 } })

      expect { schema.resolve(sources: [source]) }.to raise_error(Disposita::VersionError)
    end
  end

  describe "environment and runtime precedence" do
    it "places environment above supplied sources and runtime above environment" do
      global = Disposita::Sources::Memory.new({ git: { port: 22, transport: :ssh } }, name: :global)
      env = { "SCM_GIT_PORT" => "2222", "SCM_GIT_TRANSPORT" => "https" }

      environment = Disposita::Sources::Environment.new(env: env, prefix: "SCM")
      runtime = Disposita::Sources::Memory.new({ git: { port: 2022 } }, name: :runtime)
      config = schema.resolve(sources: [runtime, environment, global])

      expect(config.git.port).to eq(2022)
      expect(config.git.transport).to eq(:https)
      expect(config.source_of("git.port")).to eq(:runtime)
      expect(config.source_of("git.transport")).to eq(:environment)
    end
  end

  describe "writing" do
    it "validates partial data before delegating to a writable source" do
      source_class = Class.new(Disposita::Source) do
        attr_reader :written

        def writable? = true
        def read(_schema) = {}
        def write(_schema, data) = @written = data
      end
      source = source_class.new(name: :custom)

      schema.write(source, git: { transport: "https" })

      expect(source.written).to eq(version: 2, git: { transport: :https })
    end
  end

  describe "safe introspection" do
    let(:private_schema) do
      Disposita.define_schema(:app) do
        setting :token, type: String, secret: true, default: "test-secret"
        setting :optional_token, type: String, secret: true
        setting :host, type: String, default: "localhost"
      end
    end

    it "redacts secret defaults while keeping useful metadata" do
      expect(private_schema.describe(:token)).to include(default: "[REDACTED]", has_default: true,
                                                         secret: true)
      expect(private_schema.describe(:optional_token)).to include(default: nil, has_default: false)
      expect(private_schema.describe(:host)).to include(default: "localhost")
      expect(private_schema.resolve.token).to eq("test-secret")
    end

    it "accepts frozen paths without modifying caller input" do
      path = ["host"].freeze
      expect(private_schema.describe(path)[:path]).to eq("host")
      expect(path).to eq(["host"])
    end

    it "returns nil for unknown definitions" do
      expect(private_schema.describe(:missing)).to be_nil
    end
  end

  describe "invalid input" do
    it "rejects malformed persisted versions" do
      source = Disposita::Sources::Memory.new({ version: "invalid" })
      expect { schema.resolve(sources: [source]) }.to raise_error(Disposita::VersionError, /integer/)
    end

    it "rejects uncoercible values with the setting path" do
      source = Disposita::Sources::Memory.new({ git: { port: "invalid" } })
      expect { schema.resolve(sources: [source]) }.to raise_error(Disposita::CoercionError, /git.port/)
    end

    it "rejects writes to read-only sources" do
      source = Disposita::Sources::Memory.new({})
      expect { schema.write(source, git: { port: 22 }) }.to raise_error(Disposita::SaveError, /read-only/)
    end

    it "honors disabled coercion" do
      strict = Disposita.define_schema(:app) { setting :port, type: Integer, coerce: false }
      source = Disposita::Sources::Memory.new({ port: "22" })
      expect { strict.resolve(sources: [source]) }.to raise_error(Disposita::ValidationError)
    end
  end
end
