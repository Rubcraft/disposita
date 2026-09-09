# frozen_string_literal: true

# Top-level public API contracts for Disposita.
#
# These examples verify schema construction through Disposita.define and guard
# the no-side-effect entry point expected by gems and applications.

RSpec.describe Disposita do
  describe ".define" do
    it "returns an independent schema" do
      schema = described_class.define(:example) do
        setting :name, type: String
      end

      expect(schema).to be_a(Disposita::Schema)
      expect(schema.name).to eq(:example)
      expect(schema.version).to eq(1)
    end

    it "requires a definition block" do
      expect { described_class.define(:example) }.to raise_error(Disposita::SchemaError)
    end
  end

  it "does not read files or environment values when declaring a schema" do
    allow(File).to receive(:read).and_raise("unexpected file read")
    allow(ENV).to receive(:[]).and_raise("unexpected environment read")
    schema = described_class.define(:app) { setting :name, type: String, env: "APP_NAME" }
    expect(schema.name).to eq(:app)
  end
end
