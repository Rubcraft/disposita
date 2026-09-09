# frozen_string_literal: true

# End-to-end first-source-wins contracts across explicit source types.
# These regressions bind nested merge results to provenance and explain,
# distinguish presence from truthiness, and keep defaults as the final fallback.

RSpec.describe Disposita::Schema do
  let(:schema) do
    Disposita.define_schema(:app) do
      namespace :server do
        setting :host, type: String, default: "localhost"
        setting :port, type: Integer, default: 3000
        namespace :tls do
          setting :enabled, type: Disposita::Types.boolean, default: true
          setting :peers, type: Disposita::Types.array(String), default: ["default"]
        end
      end
    end
  end

  let(:environment) do
    Disposita::Sources::Environment.new(env: { "APP_SERVER_PORT" => "5000" }, prefix: "APP")
  end
  let(:project) do
    Disposita::Sources::Memory.new(
      { server: { host: "example.com", port: 4000, tls: { enabled: false } } }, name: :project
    )
  end
  let(:global) do
    Disposita::Sources::Memory.new(
      { server: { host: "global", port: 2000, tls: { enabled: true, peers: ["global"] } } }, name: :global
    )
  end

  it "selects each nested setting from the first source providing it" do
    config = schema.resolve(sources: [environment, project, global])
    expect(config.server.to_h).to eq(
      port: 5000, host: "example.com", tls: { enabled: false, peers: ["global"] }
    )
  end

  it "reports the actual winner at every namespace depth" do
    config = schema.resolve(sources: [environment, project, global])
    expect(config.source_of("server.port")).to eq(:environment)
    expect(config.source_of("server.host")).to eq(:project)
    expect(config.source_of("server.tls.enabled")).to eq(:project)
    expect(config.source_of("server.tls.peers")).to eq(:global)
  end

  it "explains the selected coerced value and source" do
    config = schema.resolve(sources: [environment, project, global])
    expect(config.explain("server.port")).to eq(path: "server.port", value: 5000, source: :environment)
  end

  it "changes both the winning value and provenance when source order changes" do
    config = schema.resolve(sources: [global, project, environment])
    expect(config.server.port).to eq(2000)
    expect(config.source_of("server.port")).to eq(:global)
    expect(config.server.tls.enabled).to be(true)
  end

  it "falls back through absent sources and finally to defaults" do
    empty = Disposita::Sources::Memory.new({ server: { tls: {} } }, name: :empty)
    config = schema.resolve(sources: [empty, environment])
    expect(config.server.port).to eq(5000)
    expect(config.server.host).to eq("localhost")
    expect(config.source_of("server.host")).to eq(:default)
    expect(config.source_of("server.tls.peers")).to eq(:default)
  end

  it "does not consult ENV or create implicit sources when resolving defaults" do
    allow(ENV).to receive(:[]).and_raise("unexpected ENV read")
    allow(Disposita::Sources::Environment).to receive(:new).and_raise("implicit environment")
    allow(Disposita::Sources::File).to receive(:new).and_raise("implicit file")
    expect(schema.resolve.server.port).to eq(3000)
  end

  it "keeps an empty array whole over lower sources and defaults" do
    runtime = Disposita::Sources::Memory.new({ server: { tls: { peers: [] } } }, name: :runtime)
    config = schema.resolve(sources: [runtime, global])
    expect(config.server.tls.peers).to eq([])
    expect(config.source_of("server.tls.peers")).to eq(:runtime)
  end

  it "treats nil as present rather than falling back" do
    nullable = Disposita.define_schema(:nullable) { setting :value, type: NilClass, required: true }
    high = Disposita::Sources::Memory.new({ value: nil }, name: :high)
    low = Disposita::Sources::Memory.new({ value: "shadowed" }, name: :low)
    config = nullable.resolve(sources: [high, low])
    expect(config.to_h).to eq(value: nil)
    expect(config.source_of(:value)).to eq(:high)
  end

  it "validates a nil default as a present value" do
    nullable = Disposita.define_schema(:nullable) { setting :value, type: NilClass, default: nil }
    expect(nullable.resolve.explain(:value)).to eq(path: "value", value: nil, source: :default)
  end

  it "does not fall back when the winning value is invalid" do
    invalid = Disposita::Sources::Memory.new({ server: { port: "invalid" } })
    expect { schema.resolve(sources: [invalid, project]) }.to raise_error(Disposita::CoercionError)
  end

  it "does not coerce shadowed values" do
    invalid = Disposita::Sources::Memory.new({ server: { port: "invalid" } })
    expect(schema.resolve(sources: [project, invalid]).server.port).to eq(4000)
  end

  it "rejects unknown keys even in a lower priority source" do
    typo = Disposita::Sources::Memory.new({ server: { porrt: 1 } })
    expect { schema.resolve(sources: [project, typo]) }.to raise_error(Disposita::UnknownSettingError)
  end

  it "rejects unknown empty mappings" do
    typo = Disposita::Sources::Memory.new({ server: { transprot: {} } })
    expect { schema.resolve(sources: [typo]) }.to raise_error(Disposita::UnknownSettingError, /transprot/)
  end

  it "rejects scalar namespace values" do
    invalid = Disposita::Sources::Memory.new({ server: false })
    expect { schema.resolve(sources: [invalid]) }.to raise_error(Disposita::UnknownSettingError, /server/)
  end

  it "checks versions even in lower priority sources" do
    newer = Disposita::Sources::Memory.new({ version: 2 })
    expect { schema.resolve(sources: [project, newer]) }.to raise_error(Disposita::VersionError)
  end

  it "accepts older persisted versions without confusing them with gem versions" do
    older = Disposita::Sources::Memory.new({ version: "0" })
    expect(schema.resolve(sources: [older]).server.port).to eq(3000)
    expect(schema.version).to eq(1)
  end

  it "copies selected values before freezing the configuration" do
    peers = [String.new("original")]
    source = Disposita::Sources::Memory.new({ server: { tls: { peers: peers } } })
    config = schema.resolve(sources: [source])
    peers.first.replace("changed")
    expect(config.server.tls.peers).to eq(["original"])
    expect { config.server.tls.peers.first.replace("changed") }.to raise_error(FrozenError)
  end
end
