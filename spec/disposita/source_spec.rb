# frozen_string_literal: true

# Contracts for custom source defaults and required adapter methods.

RSpec.describe Disposita::Source do
  subject(:source) { described_class.new(name: "custom") }

  it "normalizes the provenance name" do
    expect(source.name).to eq(:custom)
  end

  it "defaults to read-only without secret persistence" do
    expect(source).not_to be_writable
    expect(source).not_to be_allows_secrets
  end

  it "requires adapters to implement reading" do
    expect { source.read(nil) }.to raise_error(NotImplementedError)
  end

  it "rejects writes in the base implementation" do
    expect { source.write(nil, {}) }.to raise_error(Disposita::SaveError)
  end
end
