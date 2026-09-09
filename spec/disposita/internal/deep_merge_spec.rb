# frozen_string_literal: true

# Internal contracts for Disposita's layer merge semantics.
#
# These examples pin the deliberate rule that nested hashes merge recursively
# while arrays and scalar values are replaced by the higher-precedence layer.

RSpec.describe Disposita::Internal::DeepMerge do
  it "merges nested mappings and replaces arrays/scalars" do
    left = { git: { options: { timeout: 10 }, hosts: %w[a b] } }
    right = { git: { options: { retries: 2 }, hosts: ["c"] } }

    expect(described_class.call(left, right)).to eq(
      git: { options: { timeout: 10, retries: 2 }, hosts: ["c"] }
    )
  end
end
