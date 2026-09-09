# frozen_string_literal: true

# Contracts for file-backed loading, atomic writes and secret persistence policy.
#
# These examples verify missing-file behavior, safe YAML errors, explicit writes
# and protection against accidentally storing secret settings in ordinary files.

require "tmpdir"

RSpec.describe Disposita::Sources::File do
  let(:schema) do
    Disposita.define_schema(:app) do
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

  context "with atomic persistence" do
    around do |example|
      Dir.mktmpdir do |directory|
        example.metadata[:temporary_path] = File.join(directory, "config.yml")
        example.run
      end
    end

    let(:path) { RSpec.current_example.metadata.fetch(:temporary_path) }
    let(:source) { described_class.new(path) }

    # Ordered expectations guard the preconditions for the actual rename.
    # rubocop:disable RSpec/MessageSpies
    it "flushes and fsyncs a same-directory temporary before renaming" do
      allow(Tempfile).to receive(:create).and_wrap_original do |create, *arguments, &block|
        create.call(*arguments) do |temporary|
          expect(File.dirname(temporary.path)).to eq(File.dirname(path))
          expect(temporary).to receive(:flush).ordered.and_call_original
          expect(temporary).to receive(:fsync).ordered.and_call_original
          expect(File).to receive(:rename).with(temporary.path, path).ordered.and_call_original
          block.call(temporary)
        end
      end
      source.write(schema, name: "example")
    end

    # rubocop:enable RSpec/MessageSpies

    it "keeps the previous file and cleans up if fsync fails" do
      File.write(path, "name: original")
      allow(Tempfile).to receive(:create).and_wrap_original do |create, *arguments, &block|
        create.call(*arguments) do |temporary|
          allow(temporary).to receive(:fsync).and_raise(Errno::EIO)
          block.call(temporary)
        end
      end
      expect { source.write(schema, name: "replacement") }.to raise_error(Disposita::SaveError)
      expect(File.read(path)).to eq("name: original")
      expect(Dir.children(File.dirname(path))).to eq(["config.yml"])
    end

    it "gives ordinary configuration files restrictive permissions too" do
      source.write(schema, name: "example")
      expect(File.stat(path).mode & 0o777).to eq(0o600)
    end

    it "creates parent directories only on explicit writes" do
      nested = described_class.new(File.join(path, "nested.yml"))
      expect(nested.read(schema)).to eq({})
      expect(File.exist?(path)).to be(false)
      nested.write(schema, name: "example")
      expect(File.directory?(path)).to be(true)
    end

    it "supports a codec through load and dump without depending on YAML" do
      codec = Module.new do
        def self.load(content) = { "name" => content }
        def self.dump(data) = data.fetch(:name)
      end
      custom = described_class.new(path, format: codec)
      schema.write(custom, name: "example")
      expect(File.read(path)).to eq("example")
      expect(schema.resolve(sources: [custom]).name).to eq("example")
    end

    it "persists Symbols as strings and restores them through schema coercion" do
      typed = Disposita.define_schema(:app) { setting :transport, type: Symbol }
      typed.write(source, transport: :ssh)
      expect(File.read(path)).not_to include("!ruby")
      expect(source.read(typed)).to eq(version: 1, transport: "ssh")
      expect(typed.resolve(sources: [source]).transport).to eq(:ssh)
    end

    it "writes only explicit values instead of resolved ENV, runtime or defaults" do
      typed = Disposita.define_schema(:app) do
        setting :host, type: String, default: "localhost"
        setting :port, type: Integer, default: 3000
      end
      environment = Disposita::Sources::Environment.new(env: { "APP_PORT" => "5000" }, prefix: "APP")
      runtime = Disposita::Sources::Memory.new({ host: "runtime" })
      typed.resolve(sources: [runtime, environment, source])
      typed.write(source, port: "9292")
      expect(source.read(typed)).to eq(version: 1, port: 9292)
    end

    it "rejects secrets found through nested public metadata before creating a file" do
      secret = Disposita.define_schema(:app) do
        namespace(:auth) { setting :token, type: String, secret: true }
      end
      expect { secret.write(source, auth: { token: "secret" }) }
        .to raise_error(Disposita::UnsafeSecretPersistenceError)
      expect(File.exist?(path)).to be(false)
    end

    it "reads secrets regardless of the secret persistence policy" do
      File.write(path, "token: readable")
      expect(schema.resolve(sources: [source]).token).to eq("readable")
      expect(source.allows_secret_persistence?).to be(false)
    end
  end
end
