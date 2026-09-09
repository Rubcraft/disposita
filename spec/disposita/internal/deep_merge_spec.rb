# frozen_string_literal: true

# First-argument-wins merge contracts, independent of Schema source ordering.
# Nested mappings fall back per key; arrays/scalars (including nil and false)
# are selected whole. Neither input may be changed by merging.

RSpec.describe Disposita::Internal::DeepMerge do
  it "keeps first nested values while filling holes several namespaces deep" do
    high = { server: { tls: { port: 443, enabled: false }, hosts: ["high"] } }
    low = { server: { tls: { port: 80, enabled: true, host: "low" }, hosts: ["low"] } }

    expect(described_class.call(high, low)).to eq(
      server: { tls: { port: 443, enabled: false, host: "low" }, hosts: ["high"] }
    )
  end

  it "selects a first scalar over a later mapping" do
    expect(described_class.call({ key: nil }, { key: { nested: 1 } })).to eq(key: nil)
  end

  it "selects a first mapping over a later scalar" do
    expect(described_class.call({ key: { nested: 1 } }, { key: false })).to eq(key: { nested: 1 })
  end

  it "fills an empty namespace but keeps an empty array" do
    expect(described_class.call({ namespace: {}, items: [] },
                                { namespace: { value: 1 }, items: [2] })).to eq(
                                  namespace: { value: 1 }, items: []
                                )
  end

  it "does not mutate either input" do
    high = { namespace: { value: 1 }.freeze }.freeze
    low = { namespace: { value: 2, fallback: 3 }.freeze }.freeze
    described_class.call(high, low)
    expect(high).to eq(namespace: { value: 1 })
    expect(low).to eq(namespace: { value: 2, fallback: 3 })
  end
end
