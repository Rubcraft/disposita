# frozen_string_literal: true

# DSL rejection contracts exercised through the public schema entry point.

RSpec.describe Disposita::Internal::SchemaBuilder do
  it "rejects invalid names" do
    expect { Disposita.define_schema(:app) { setting 123, type: String } }.to raise_error(Disposita::SchemaError)
  end

  it "rejects contradictory presence flags" do
    expect do
      Disposita.define_schema(:app) { setting :name, type: String, required: true, optional: true }
    end.to raise_error(Disposita::SchemaError)
  end

  ["", :"", "server.port", :"server.port"].each do |name|
    it "rejects an invalid setting segment #{name.inspect}" do
      expect { Disposita.define_schema(:app) { setting name, type: String } }
        .to raise_error(Disposita::SchemaError, /non-empty path segments without dots/)
    end

    it "rejects an invalid namespace segment #{name.inspect}" do
      expect { Disposita.define_schema(:app) { namespace(name) { setting :port, type: Integer } } }
        .to raise_error(Disposita::SchemaError, /non-empty path segments without dots/)
    end
  end

  [["server-name", "port number"], %i[server port]].each do |namespace_name, setting_name|
    it "accepts valid #{namespace_name.class} segments without imposing naming conventions" do
      schema = Disposita.define_schema(:app) do
        namespace(namespace_name) { setting setting_name, type: Integer, default: 3000 }
      end
      expect(schema.describe("#{namespace_name}.#{setting_name}")[:default]).to eq(3000)
      expect(schema.resolve.to_h).to eq(namespace_name.to_sym => { setting_name.to_sym => 3000 })
    end
  end

  it "stores deeply frozen defaults internally" do
    builder = described_class.new
    builder.setting(:options, type: Hash, default: { hosts: [String.new("one")] })
    stored = builder.settings.first.default
    expect(stored).to be_frozen
    expect(stored[:hosts]).to be_frozen
    expect(stored[:hosts].first).to be_frozen
  end
end
