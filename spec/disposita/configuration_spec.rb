# frozen_string_literal: true

# Contracts for immutable resolved configuration values.
#
# These examples verify ergonomic access, detached exports, source provenance
# and the guarantee that secret settings are redacted from diagnostics while
# remaining available to application code.

RSpec.describe Disposita::Configuration do
  subject(:config) do
    schema.resolve([
                     Disposita::Sources::Hash.new({ auth: { token: "secret" } }, name: :project)
                   ])
  end

  let(:schema) do
    Disposita.define(:app) do
      namespace :auth do
        setting :token, type: String, secret: true
        setting :timeout, type: Integer, default: 30
      end
    end
  end

  it "supports immutable dot and bracket access" do
    expect(config.auth.token).to eq("secret")
    expect(config[:auth][:timeout]).to eq(30)
    expect(config).to be_frozen
  end

  it "returns a detached hash" do
    copy = config.to_h
    copy[:auth][:timeout] = 99

    expect(config.auth.timeout).to eq(30)
  end

  it "redacts secret values from inspect" do
    expect(config.inspect).to include("token=[REDACTED]")
    expect(config.inspect).not_to include("secret")
  end

  it "redacts secrets from explain" do
    expect(config.explain("auth.token")).to eq(
      path: "auth.token",
      value: "[REDACTED]",
      source: :project
    )
  end

  it "preserves frozen caller paths for provenance and explanations" do
    path = %w[auth timeout].freeze
    expect(config.source_of(path)).to eq(:default)
    expect(config.explain(path)[:value]).to eq(30)
    expect(path).to eq(%w[auth timeout])
  end

  it "reports unknown keys and methods consistently" do
    expect { config[:missing] }.to raise_error(KeyError)
    expect { config.auth.missing }.to raise_error(NoMethodError)
    expect { config.auth(1) }.to raise_error(NoMethodError)
    expect { config.explain(:missing) }.to raise_error(KeyError)
  end

  it "exports detached namespaces and redacts their inspection" do
    copy = config.auth.to_h
    copy[:token].replace("changed")
    expect(config.auth.token).to eq("secret")
    expect(config.auth.inspect).not_to include("secret")
    expect(config.auth).to respond_to(:timeout)
    expect(config).not_to respond_to(:missing)
  end
end
