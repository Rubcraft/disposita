# frozen_string_literal: true

# Contracts for file-backed loading, atomic writes and secret persistence policy.
#
# These examples verify missing-file behavior, safe YAML errors, explicit writes
# and protection against accidentally storing secret settings in ordinary files.

require "tmpdir"

RSpec.describe Disposita::Sources::File do
  let(:schema) do
    Disposita.define(:app) do
      setting :name, type: String
      setting :token, type: String, secret: true
    end
  end

  it "returns an empty layer when the file does not exist" do
    Dir.mktmpdir do |directory|
      source = described_class.new(File.join(directory, "missing.yml"))
      expect(source.read(schema)).to eq({})
    end
  end

  it "writes and reads safe YAML atomically" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "config.yml")
      source = described_class.new(path)

      source.write(schema, version: 1, name: "example")

      expect(source.read(schema)).to eq(version: 1, name: "example")
    end
  end

  it "rejects secret persistence by default" do
    Dir.mktmpdir do |directory|
      source = described_class.new(File.join(directory, "config.yml"))

      expect do
        source.write(schema, token: "secret")
      end.to raise_error(Disposita::UnsafeSecretPersistenceError)
    end
  end

  it "allows explicitly opted-in secret persistence and tightens permissions" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "private.yml")
      source = described_class.new(path, allow_secrets: true)

      source.write(schema, token: "secret")

      expect(File.stat(path).mode & 0o777).to eq(0o600)
    end
  end

  context "with an existing file" do
    around do |example|
      Dir.mktmpdir do |directory|
        example.metadata[:temporary_path] = File.join(directory, "config.yml")
        example.run
      end
    end

    let(:path) { RSpec.current_example.metadata.fetch(:temporary_path) }
    let(:source) { described_class.new(path) }

    it "propagates YAML parse errors" do
      File.write(path, "key: [")
      expect { source.read(schema) }.to raise_error(Disposita::ParseError)
    end

    it "wraps read failures" do
      File.write(path, "name: original")
      allow(File).to receive(:read).with(path).and_raise(Errno::EACCES)
      expect { source.read(schema) }.to raise_error(Disposita::LoadError)
    end

    it "preserves the previous file and removes the temporary file when replacement fails" do
      File.write(path, "name: original")
      allow(File).to receive(:rename).and_raise(Errno::EACCES)
      expect { source.write(schema, name: "replacement") }.to raise_error(Disposita::SaveError)
      expect(File.read(path)).to eq("name: original")
      expect(Dir.children(File.dirname(path))).to eq(["config.yml"])
    end
  end
end
