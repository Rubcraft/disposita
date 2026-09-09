# frozen_string_literal: true

# Contracts for safe YAML parsing and serialization.
#
# These examples verify that configuration stays data-only: unsafe Ruby object
# loading and aliases are rejected, roots must be mappings and symbols serialize
# to portable strings.

RSpec.describe Disposita::Formats::YAML do
  it "round-trips primitive configuration data" do
    yaml = described_class.dump(version: 1, git: { transport: :ssh })

    expect(described_class.load(yaml)).to eq("version" => 1, "git" => { "transport" => "ssh" })
  end

  it "rejects Ruby object deserialization" do
    yaml = "--- !ruby/object:Object {}\n"

    expect { described_class.load(yaml) }.to raise_error(Disposita::ParseError)
  end

  it "requires a mapping at the document root" do
    expect { described_class.load("---\n- a\n- b\n") }.to raise_error(Disposita::ParseError, /mapping/)
  end

  it "rejects aliases" do
    expect { described_class.load("first: &value {}\nsecond: *value\n") }.to raise_error(Disposita::ParseError)
  end

  it "rejects malformed YAML" do
    expect { described_class.load("key: [") }.to raise_error(Disposita::ParseError)
  end

  it "treats empty documents as empty layers" do
    expect(described_class.load("")).to eq({})
  end

  it "serializes array members as portable primitives" do
    expect(described_class.load(described_class.dump(items: [:ssh, 2]))).to eq("items" => ["ssh", 2])
  end
end
