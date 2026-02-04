# frozen_string_literal: true

require "active_support/notifications"
# ActiveSupport 8.1+ expects this constant when local cache is used.
begin
  require "active_support/isolated_execution_state"
rescue LoadError
end
require "securerandom"
require "cache/swr/version"
require "cache/swr/lock"

module Cache
  module SWR
    class Error < StandardError; end

    DEFAULT_LOCK_TTL = 5
    VALID_REFRESH = [nil, :async, :sync].freeze

    def self.fetch(key, ttl:, swr:, store: nil, refresh: :async, lock: true, lock_ttl: DEFAULT_LOCK_TTL,
                   lock_client: nil, &block)
      raise ArgumentError, "block required" unless block
      validate_refresh!(refresh)

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

      compute_and_store(key, ttl, swr, store, lock_ttl, lock_client, lock: lock, &block)
    end

    def self.default_store
      return Rails.cache if defined?(Rails) && Rails.respond_to?(:cache)
      raise Error, "store is required when Rails.cache is unavailable"
    end

    def self.valid_payload?(payload)
      payload.is_a?(Hash) && payload.key?(:value) && payload.key?(:expires_at) && payload.key?(:stale_until)
    end

    def self.compute_and_store(key, ttl, swr, store, lock_ttl, lock_client, lock: true, lock_key: nil,
                               lock_token: nil, release_lock: false)
      lock_key ||= lock_key_for(key)
      token = lock_token || SecureRandom.uuid
      owns_lock = false
      if lock
        lock_client ||= Lock.default_for(store) if lock_client.nil?
        if lock_client
          owns_lock = lock_client.acquire(lock_key, token, lock_ttl)
          unless owns_lock
            existing = store.read(key)
            return existing[:value] if valid_payload?(existing)
          end
        end
      elsif release_lock
        owns_lock = true
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
      lock_client.release(lock_key, token) if lock_client && owns_lock
    end

    def self.trigger_refresh(key, ttl, swr, store, refresh, lock, lock_ttl, lock_client, &block)
      return if refresh.nil?

      lock_client ||= Lock.default_for(store) if lock && lock_client.nil?
      lock_key = lock_key_for(key)

      token = nil
      if lock && lock_client
        token = SecureRandom.uuid
        return unless lock_client.acquire(lock_key, token, lock_ttl)
      end

      runner = lambda do
        compute_and_store(key, ttl, swr, store, lock_ttl, lock_client,
                          lock: false, lock_key: lock_key, lock_token: token,
                          release_lock: lock && lock_client, &block)
      end

      refresh == :async ? Thread.new { runner.call } : runner.call
    end

    def self.lock_key_for(key)
      "cache-swr:lock:#{key}"
    end

    def self.validate_refresh!(refresh)
      return if VALID_REFRESH.include?(refresh)
      raise ArgumentError, "refresh must be :async, :sync, or nil"
    end
  end
end

require "cache/swr/railtie"
