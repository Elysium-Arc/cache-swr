# frozen_string_literal: true

require "cache/swr/version"
require "cache/swr/lock"

module Cache
  module SWR
    class Error < StandardError; end

    DEFAULT_LOCK_TTL = 5

    def self.fetch(key, ttl:, swr:, store: nil, refresh: :async, lock: true, lock_ttl: DEFAULT_LOCK_TTL,
                   lock_client: nil, &block)
      raise ArgumentError, "block required" unless block

      store ||= default_store
      payload = store.read(key)
      now = Time.now

      if valid_payload?(payload)
        if now < payload[:expires_at]
          return payload[:value]
        end

        if now < payload[:stale_until]
          trigger_refresh(key, ttl, swr, store, refresh, lock, lock_ttl, lock_client, &block)
          return payload[:value]
        end
      end

      compute_and_store(key, ttl, swr, store, lock_ttl, lock_client, &block)
    end

    def self.default_store
      return Rails.cache if defined?(Rails) && Rails.respond_to?(:cache)
      raise Error, "store is required when Rails.cache is unavailable"
    end

    def self.valid_payload?(payload)
      payload.is_a?(Hash) && payload.key?(:value) && payload.key?(:expires_at) && payload.key?(:stale_until)
    end

    def self.compute_and_store(key, ttl, swr, store, lock_ttl, lock_client, lock: true)
      lock_key = lock_key_for(key)
      acquired = false
      if lock
        lock_client ||= Lock.default_for(store) if lock_client.nil?
        if lock_client
          acquired = lock_client.acquire(lock_key, "compute", lock_ttl)
          unless acquired
            existing = store.read(key)
            return existing[:value] if valid_payload?(existing)
          end
        end
      end

      value = yield
      payload = {
        value: value,
        expires_at: Time.now + ttl,
        stale_until: Time.now + ttl + swr
      }
      store.write(key, payload, expires_in: ttl + swr)
      value
    ensure
      lock_client.release(lock_key, "compute") if lock_client && acquired
    end

    def self.trigger_refresh(key, ttl, swr, store, refresh, lock, lock_ttl, lock_client, &block)
      return if refresh.nil?

      lock_client ||= Lock.default_for(store) if lock && lock_client.nil?
      lock_key = lock_key_for(key)

      acquired = false
      if lock && lock_client
        acquired = lock_client.acquire(lock_key, "refresh", lock_ttl)
        return unless acquired
      end

      if refresh == :async
        Thread.new do
          compute_and_store(key, ttl, swr, store, lock_ttl, lock_client, lock: lock, &block)
        end
      else
        compute_and_store(key, ttl, swr, store, lock_ttl, lock_client, lock: lock, &block)
      end
    ensure
      lock_client.release(lock_key, "refresh") if lock_client && acquired
    end

    def self.lock_key_for(key)
      "cache-swr:lock:#{key}"
    end
  end
end

require "cache/swr/railtie" if defined?(Rails)
