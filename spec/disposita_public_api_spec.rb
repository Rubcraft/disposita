# frozen_string_literal: true

# Public extension and introspection contracts for 0.2.0.
# Legacy entry points are absent; custom Sources need only immutable metadata,
# and internal records or secret values must not leak through public diagnostics.

RSpec.describe Disposita do
  let(:schema) do
    described_class.define_schema(:app) do
      setting :port, type: Integer, default: 3000
      setting :token, type: Integer, secret: true, env: "APP_TOKEN"
      setting :names, type: Disposita::Types.array(String), default: ["default"]
      setting :optional, type: String
    end
  end

  it "exposes a single schema factory without legacy aliases" do
    expect(described_class).to respond_to(:define_schema)
    expect(described_class).not_to respond_to(:define, :schema)
    expect(Disposita::Sources.const_defined?(:Hash, false)).to be(false)
  end

  it "exposes metadata instead of internal definitions and removes load" do
    expect(schema).to respond_to(:resolve, :describe, :each_setting)
    expect(schema).not_to respond_to(:load, :settings, :setting)
    expect { schema.resolve([]) }.to raise_error(ArgumentError)
  end

  it "rejects removed special source keywords" do
    expect { schema.resolve(env: {}) }.to raise_error(ArgumentError)
    expect { schema.resolve(env_prefix: "APP") }.to raise_error(ArgumentError)
    expect { schema.resolve(overrides: {}) }.to raise_error(ArgumentError)
  end

  it "provides an enumerator of metadata in declaration order" do
    expect(schema.each_setting).to be_an(Enumerator)
    expect(schema.each_setting.map { |item| item[:path] }).to eq(%w[port token names optional])
    expect(schema.each_setting.to_a).to all(be_a(Hash))
    expect(schema.each_setting { |_item| nil }).to equal(schema)
  end

  it "deeply freezes detached metadata without changing schema defaults" do
    metadata = schema.describe(:names)
    expect { metadata[:default].first.replace("changed") }.to raise_error(FrozenError)
    expect { metadata[:path].replace("changed") }.to raise_error(FrozenError)
    expect(schema.resolve.names).to eq(["default"])
  end

  it "lets custom Sources discover names and paths through public metadata" do
    adapter = Class.new(Disposita::Source) do
      def read(schema)
        schema.each_setting.to_h { |item| [item.fetch(:path).to_sym, item[:default]] }
              .slice(:port)
      end
    end
    config = schema.resolve(sources: [adapter.new(name: :custom)])
    expect(config.port).to eq(3000)
    expect(config.source_of(:port)).to eq(:custom)
  end

  it "keeps platform and serialization helpers private" do
    expect(Disposita::Paths).not_to respond_to(:macos?, :windows?, :config_home, :home_path)
    expect(Disposita::Formats::YAML).not_to respond_to(:stringify)
    expect(Disposita::Source.new(name: :custom)).not_to respond_to(:allows_secrets?)
  end

  it "explains absent optional settings without leaking an internal sentinel" do
    expect(schema.resolve.explain(:optional)).to eq(path: "optional", value: nil, source: nil)
    expect(schema.resolve.to_h).not_to have_key(:optional)
  end

  it "does not read explicit ENV setting names without an Environment source" do
    allow(ENV).to receive(:[]).with("APP_TOKEN").and_raise("implicit ENV")
    allow(ENV).to receive(:key?).with("APP_TOKEN").and_raise("implicit ENV")
    expect(schema.resolve.to_h).not_to have_key(:token)
  end

  it "redacts a winning secret while preserving its provenance" do
    high = Disposita::Sources::Memory.new({ token: "123" }, name: :high)
    low = Disposita::Sources::Memory.new({ token: "456" }, name: :low)
    config = schema.resolve(sources: [high, low])
    expect(config.token).to eq(123)
    expect(config.explain(:token)).to eq(path: "token", value: "[REDACTED]", source: :high)
    expect(config.inspect).not_to include("123", "456")
  end

  it "redacts invalid secrets from the entire coercion exception chain" do
    source = Disposita::Sources::Memory.new({ token: "invalid-secret" })
    expect { schema.resolve(sources: [source]) }.to raise_error(Disposita::CoercionError) { |error|
      expect(error.full_message).not_to include("invalid-secret")
      expect(error.message).to include("token", "[REDACTED]")
    }
  end
end
