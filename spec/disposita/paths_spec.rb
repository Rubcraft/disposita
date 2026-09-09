# frozen_string_literal: true

# Contracts for cross-platform configuration path resolution.
#
# These examples pin Linux/XDG, macOS and Windows conventions and verify that
# project-local paths cannot escape the consumer-selected project root.

RSpec.describe Disposita::Paths do
  describe ".user_config" do
    it "uses XDG on Linux when available" do
      path = described_class.user_config(
        "scm",
        env: { "HOME" => "/home/user", "XDG_CONFIG_HOME" => "/custom" },
        host_os: "linux"
      )

      expect(path).to eq("/custom/scm")
    end

    it "uses Application Support on macOS" do
      path = described_class.user_config("scm", env: { "HOME" => "/Users/me" }, host_os: "darwin")

      expect(path).to eq("/Users/me/Library/Application Support/scm")
    end

    it "uses APPDATA on Windows" do
      path = described_class.user_config("scm", env: { "APPDATA" => "C:/Users/me/AppData/Roaming" },
                                                host_os: "mingw")

      expect(path).to eq("C:/Users/me/AppData/Roaming/scm")
    end
  end

  describe ".project" do
    it "rejects paths escaping the project root" do
      expect do
        described_class.project("/tmp/project", "../secret.yml")
      end.to raise_error(Disposita::PathError)
    end
  end

  it "uses HOME when XDG is absent" do
    expect(described_class.user_config("app", env: { "HOME" => "/home/me" }, host_os: "linux"))
      .to eq("/home/me/.config/app")
  end

  it "uses LOCALAPPDATA when APPDATA is absent" do
    expect(described_class.user_config("app", env: { "LOCALAPPDATA" => "C:/local" }, host_os: "mingw"))
      .to eq("C:/local/app")
  end

  %w[linux darwin mingw].each do |platform|
    it "reports unavailable directories on #{platform}" do
      expect { described_class.user_config("app", env: {}, host_os: platform) }.to raise_error(Disposita::PathError)
    end
  end

  it "rejects empty application names" do
    expect { described_class.user_config("") }.to raise_error(Disposita::PathError)
  end

  it "accepts the root and descendants" do
    expect(described_class.project("/tmp/app", ".")).to eq("/tmp/app")
    expect(described_class.project("/tmp/app", "config.yml")).to eq("/tmp/app/config.yml")
  end
end
