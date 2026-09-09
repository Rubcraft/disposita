# frozen_string_literal: true

# Contracts for environment-backed configuration layers.
#
# These examples verify explicit variable names, generated prefixes and the rule
# that ENV contributes raw values while schema coercion happens later.

RSpec.describe Disposita::Sources::Environment do
  let(:schema) do
    Disposita.define(:app) do
      namespace :git do
        setting :remote, type: String
        setting :token, type: String, env: "CUSTOM_TOKEN"
      end
    end
  end

  it "uses explicit environment names before generated names" do
    source = described_class.new(
      env: { "APP_GIT_REMOTE" => "upstream", "CUSTOM_TOKEN" => "abc" },
      prefix: "APP"
    )

    expect(source.read(schema)).to eq(git: { remote: "upstream", token: "abc" })
  end
end
