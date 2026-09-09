# frozen_string_literal: true

# Contracts for normalized in-memory source data and provenance.

RSpec.describe Disposita::Sources::Hash do
  it "normalizes nested keys, including mappings inside arrays" do
    source = described_class.new({ "items" => [{ "name" => "first" }] }, name: :runtime)
    expect(source.read(nil)).to eq(items: [{ name: "first" }])
    expect(source.name).to eq(:runtime)
  end
end
