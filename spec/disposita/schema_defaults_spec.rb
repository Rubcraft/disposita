# frozen_string_literal: true

# Schema defaults are declaration-time snapshots of ordinary Ruby data trees.
# Caller mutation and metadata access cannot change stored defaults; absent
# defaults remain distinct from explicit nil, and sources still take priority.

RSpec.describe Disposita::Schema do
  it "isolates array defaults from later caller mutations" do
    items = [String.new("a")]
    schema = Disposita.define_schema(:app) do
      setting :items, type: Disposita::Types.array(String), default: items
    end
    items.first.replace("changed")
    items << "b"
    expect(schema.resolve.items).to eq(["a"])
    expect(items).to eq(%w[changed b])
  end

  it "isolates nested hashes and their arrays, strings and scalars" do
    options = { hosts: [String.new("one"), "two"], options: { enabled: true } }
    schema = Disposita.define_schema(:app) { setting :options, type: Hash, default: options }
    options[:hosts].first.replace("changed")
    options[:hosts] << "three"
    options[:options][:enabled] = false
    options[:extra] = "later"
    expect(schema.resolve.to_h[:options]).to eq(hosts: %w[one two], options: { enabled: true })
    expect(schema.describe(:options)[:default]).to eq(hosts: %w[one two], options: { enabled: true })
  end

  it "isolates standalone String defaults without freezing the caller's string" do
    name = String.new("original")
    schema = Disposita.define_schema(:app) { setting :name, type: String, default: name }
    name.replace("changed")
    expect(schema.resolve.name).to eq("original")
    expect(name).not_to be_frozen
  end

  it "prevents indirect changes through metadata defaults" do
    schema = Disposita.define_schema(:app) do
      setting :options, type: Hash, default: { hosts: ["one"], flags: { enabled: true } }
    end
    metadata = schema.describe(:options)
    expect { metadata[:default][:hosts] << "two" }.to raise_error(FrozenError)
    expect { metadata[:default][:hosts].first.replace("changed") }.to raise_error(FrozenError)
    expect { metadata[:default][:flags][:enabled] = false }.to raise_error(FrozenError)
    expect(schema.resolve.to_h[:options]).to eq(hosts: ["one"], flags: { enabled: true })
  end

  it "keeps absent defaults distinct from explicit nil and immutable scalars" do
    schema = Disposita.define_schema(:app) do
      setting :absent, type: String
      setting :nothing, type: NilClass, default: nil, required: true
      setting :enabled, type: Disposita::Types.boolean, default: false
      setting :count, type: Integer, default: 3
    end
    expect(schema.describe(:absent)[:has_default]).to be(false)
    expect(schema.describe(:nothing)[:has_default]).to be(true)
    expect(schema.resolve.to_h).to eq(nothing: nil, enabled: false, count: 3)
  end

  it "still uses explicit sources before the isolated default" do
    items = ["default"]
    schema = Disposita.define_schema(:app) do
      setting :items, type: Disposita::Types.array(String), default: items
    end
    high = Disposita::Sources::Memory.new({ items: ["high"] }, name: :high)
    low = Disposita::Sources::Memory.new({ items: ["low"] }, name: :low)
    expect(schema.resolve(sources: [high, low]).items).to eq(["high"])
    expect(schema.resolve.items).to eq(["default"])
  end
end
