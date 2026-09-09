# frozen_string_literal: true

# Contracts for environment-backed configuration layers.
#
# These examples verify explicit variable names, generated prefixes and the rule
# that ENV contributes raw values while schema coercion happens later.

RSpec.describe Disposita::Sources::Environment do
  let(:schema) do
    Disposita.define_schema(:app) do
      namespace :git do
        setting :remote, type: String
        setting :token, type: String, env: "CUSTOM_TOKEN"
      end
    end
  end

  it "uses explicit environment names before generated names" do
    source = described_class.new(
      env: { "APP_GIT_REMOTE" => "upstream", "CUSTOM_TOKEN" => "abc", "APP_GIT_TOKEN" => "ignored" },
      prefix: "APP"
    )

    expect(source.read(schema)).to eq(git: { remote: "upstream", token: "abc" })
  end

  it "does not fall back to the derived name when an explicit variable is absent" do
    source = described_class.new(env: { "APP_GIT_TOKEN" => "ignored" }, prefix: "APP")
    expect(source.read(schema)).to eq({})
  end

  it "reads only explicitly named settings when no prefix is given" do
    source = described_class.new(env: { "CUSTOM_TOKEN" => "abc", "APP_GIT_REMOTE" => "ignored" })
    expect(source.read(schema)).to eq(git: { token: "abc" })
  end

  it "uses process ENV only when the caller explicitly creates this source" do
    allow(ENV).to receive(:key?).with("CUSTOM_TOKEN").and_return(true)
    allow(ENV).to receive(:fetch).with("CUSTOM_TOKEN").and_return("raw")
    expect(described_class.new.read(schema)).to eq(git: { token: "raw" })
  end
end
