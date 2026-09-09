# frozen_string_literal: true

# Contracts for primitive coercion and custom type protocols.

RSpec.describe Disposita::Internal::TypeAdapter do
  [[String, 12, "12"], [Integer, "12", 12], [Float, "1.5", 1.5],
   [Symbol, "ssh", :ssh]].each do |type, raw, expected|
    it "coerces serialized #{type} values" do
      expect(described_class.coerce(type, raw)).to eq(expected)
    end
  end

  [[Integer, "bad"], [Symbol, 12], [Hash, "bad"]].each do |type, raw|
    it "rejects unsupported #{type} coercion" do
      expect { described_class.coerce(type, raw) }.to raise_error(Disposita::CoercionError)
    end
  end

  it "preserves already valid input" do
    expect(described_class.coerce(Integer, 12)).to eq(12)
  end

  it "uses custom validation and coercion" do
    type = Disposita::Types.enum(:ssh)
    expect(described_class.coerce(type, "ssh")).to eq(:ssh)
  end

  it "describes anonymous classes" do
    type = Class.new
    expect(described_class.describe(type)).to eq(type.inspect)
  end

  it "rejects unsupported custom coercion through the documented error class" do
    type = Object.new
    def type.valid?(_value) = false
    expect { described_class.coerce(type, "input") }.to raise_error(Disposita::CoercionError)
  end
end
