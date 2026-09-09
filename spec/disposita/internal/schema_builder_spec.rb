# frozen_string_literal: true

# DSL rejection contracts exercised through the public schema entry point.

RSpec.describe Disposita::Internal::SchemaBuilder do
  it "rejects invalid names" do
    expect { Disposita.define(:app) { setting 123, type: String } }.to raise_error(Disposita::SchemaError)
  end

  it "rejects contradictory presence flags" do
    expect do
      Disposita.define(:app) { setting :name, type: String, required: true, optional: true }
    end.to raise_error(Disposita::SchemaError)
  end
end
