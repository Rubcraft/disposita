# frozen_string_literal: true

# Contracts for Disposita's configuration-oriented type helpers.
#
# The examples focus on behavior needed by serialized and ENV-backed settings:
# boolean coercion, finite enums and homogeneous array validation.

RSpec.describe Disposita::Types do
  describe ".boolean" do
    it "coerces conventional true and false strings" do
      type = described_class.boolean

      expect(type.coerce("YES")).to be(true)
      expect(type.coerce("off")).to be(false)
    end
  end

  describe ".enum" do
    it "coerces strings to symbol members" do
      type = described_class.enum(:ssh, :https)

      expect(type.coerce("https")).to eq(:https)
    end
  end

  describe ".array" do
    it "validates member types" do
      type = described_class.array(String)

      expect(type.valid?(%w[a b])).to be(true)
      expect(type.valid?(["a", 1])).to be(false)
    end
  end

  it "accepts existing booleans and rejects ambiguous input" do
    expect(described_class.boolean.coerce(false)).to be(false)
    expect { described_class.boolean.coerce("maybe") }.to raise_error(ArgumentError)
  end

  it "rejects empty enums and values outside their members" do
    expect { described_class.enum }.to raise_error(ArgumentError)
    expect { described_class.enum(:ssh).coerce("ftp") }.to raise_error(ArgumentError)
    expect(described_class.enum(:ssh).coerce(:ssh)).to eq(:ssh)
    expect(described_class.enum(:ssh).inspect).to eq("enum(:ssh)")
  end

  it "coerces array members and rejects non-arrays" do
    type = described_class.array(Integer)
    expect(type.coerce(%w[1 2])).to eq([1, 2])
    expect { type.coerce("1,2") }.to raise_error(ArgumentError)
    expect(type.inspect).to eq("Array[Integer]")
  end
end
