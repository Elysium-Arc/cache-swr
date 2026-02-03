# frozen_string_literal: true

require "active_support/cache"

RSpec.describe Cache::SWR do
  it "raises when no store is available" do
    expect { described_class.default_store }.to raise_error(Cache::SWR::Error)
  end

  it "uses Rails.cache when available" do
    store = ActiveSupport::Cache::MemoryStore.new
    stub_const("Rails", Module.new)
    Rails.define_singleton_method(:cache) { store }

    expect(described_class.default_store).to eq(store)
  end

  it "returns cached value while fresh" do
    store = ActiveSupport::Cache::MemoryStore.new
    payload = { value: "v1", expires_at: Time.now + 10, stale_until: Time.now + 20 }
    store.write("key", payload)

    expect(described_class.fetch("key", ttl: 1, swr: 1, store: store, lock: false) { "v2" }).to eq("v1")
  end

  it "recomputes when payload is invalid" do
    store = ActiveSupport::Cache::MemoryStore.new
    store.write("key", "invalid")

    value = described_class.fetch("key", ttl: 0.01, swr: 0.01, store: store, refresh: :sync, lock: false) { "fresh" }
    expect(value).to eq("fresh")
  end

  it "serves stale while refreshing" do
    store = ActiveSupport::Cache::MemoryStore.new
    value1 = described_class.fetch("key", ttl: 0.05, swr: 1, store: store, refresh: :sync, lock: false) { "v1" }
    expect(value1).to eq("v1")

    sleep 0.06

    value2 = described_class.fetch("key", ttl: 0.05, swr: 1, store: store, refresh: :sync, lock: false) { "v2" }
    expect(value2).to eq("v1")

    fresh = described_class.fetch("key", ttl: 0.05, swr: 1, store: store, refresh: :sync, lock: false) { "v3" }
    expect(fresh).to eq("v2")
  end

  it "recomputes when stale window has passed" do
    store = ActiveSupport::Cache::MemoryStore.new
    described_class.fetch("key", ttl: 0.01, swr: 0.01, store: store, refresh: :sync, lock: false) { "v1" }

    sleep 0.03

    value = described_class.fetch("key", ttl: 0.01, swr: 0.01, store: store, refresh: :sync, lock: false) { "v2" }
    expect(value).to eq("v2")
  end

  it "skips refresh when refresh is nil" do
    store = ActiveSupport::Cache::MemoryStore.new
    described_class.fetch("key", ttl: 0.01, swr: 1, store: store, refresh: :sync, lock: false) { "v1" }

    sleep 0.02

    value = described_class.fetch("key", ttl: 0.01, swr: 1, store: store, refresh: nil, lock: false) { "v2" }
    expect(value).to eq("v1")
  end

  it "triggers async refresh" do
    store = ActiveSupport::Cache::MemoryStore.new
    described_class.fetch("key", ttl: 0.01, swr: 1, store: store, refresh: :sync, lock: false) { "v1" }

    sleep 0.02

    described_class.fetch("key", ttl: 0.01, swr: 1, store: store, refresh: :async, lock: false) { "v2" }

    sleep 0.02

    payload = store.read("key")
    expect(payload[:value]).to eq("v2")
  end

  it "raises when lock is enabled without redis-backed store" do
    store = ActiveSupport::Cache::MemoryStore.new
    expect do
      described_class.fetch("key", ttl: 0.01, swr: 0.01, store: store, refresh: :sync) { "v1" }
    end.to raise_error(Cache::SWR::Error)
  end

  it "returns existing value when lock acquisition fails" do
    store = ActiveSupport::Cache::MemoryStore.new
    payload = { value: "cached", expires_at: Time.now + 10, stale_until: Time.now + 20 }
    store.write("key", payload)

    lock_client = Class.new do
      def acquire(*_args) = false
      def release(*_args); end
    end.new

    value = described_class.fetch("key", ttl: 1, swr: 1, store: store, lock_ttl: 1, lock_client: lock_client) { "new" }
    expect(value).to eq("cached")
  end
end

RSpec.describe Cache::SWR::Lock do
  class FakeRedis
    def initialize
      @data = {}
    end

    def set(key, token, nx:, px:)
      return false if nx && @data.key?(key)
      @data[key] = token
      true
    end

    def eval(_script, keys:, argv:)
      if @data[keys[0]] == argv[0]
        @data.delete(keys[0])
        1
      else
        0
      end
    end
  end

  class RedisWith
    def initialize(redis)
      @redis = redis
    end

    def with
      yield @redis
    end
  end

  class ErrorRedis
    def eval(*_args)
      raise "boom"
    end

    def set(*_args)
      true
    end
  end

  it "builds a redis lock for stores exposing redis" do
    store = Struct.new(:redis).new(FakeRedis.new)
    lock = described_class.default_for(store)
    expect(lock).to be_a(Cache::SWR::Lock::RedisLock)
  end

  it "raises when store does not expose redis" do
    expect { described_class.default_for(Object.new) }.to raise_error(Cache::SWR::Error)
  end

  it "acquires and releases redis locks" do
    redis = FakeRedis.new
    lock = Cache::SWR::Lock::RedisLock.new(redis)

    expect(lock.acquire("key", "token", 1)).to eq(true)
    expect(lock.release("key", "token")).to eq(1)
  end

  it "uses #with when available" do
    redis = FakeRedis.new
    lock = Cache::SWR::Lock::RedisLock.new(RedisWith.new(redis))

    expect(lock.acquire("key", "token", 1)).to eq(true)
  end

  it "returns false when release fails" do
    lock = Cache::SWR::Lock::RedisLock.new(ErrorRedis.new)
    expect(lock.release("key", "token")).to eq(false)
  end
end
