# Cache SWR

Server-side stale-while-revalidate caching for Rails.

## About
Cache SWR stores a value plus two time windows: a fresh window and a stale window. Within the fresh window, values are returned immediately. Within the stale window, stale values are returned while a refresh runs in the background (or inline if you prefer).

This pattern reduces tail latency and keeps caches warm without blocking callers.

## Compatibility
- Ruby 3.0+
- ActiveSupport 6.1+
- Works with ActiveSupport cache stores
- Redis-backed stores are recommended when locking is enabled

## Installation
```ruby
# Gemfile

gem "cache-swr"
```

## Usage
```ruby
value = Cache::SWR.fetch("expensive-key", ttl: 60, swr: 300, store: Rails.cache) do
  ExpensiveQuery.call
end
```

Rails integration adds `Rails.cache.fetch_swr`:
```ruby
Rails.cache.fetch_swr("expensive-key", ttl: 60, swr: 300) { ExpensiveQuery.call }
```

If you are using an in-memory store, disable locking:
```ruby
Cache::SWR.fetch("key", ttl: 30, swr: 120, store: ActiveSupport::Cache::MemoryStore.new, lock: false) do
  compute
end
```

## Options
- `ttl` (Integer) fresh window in seconds
- `swr` (Integer) stale window in seconds
- `refresh` (`:async`, `:sync`, or `nil`) refresh strategy
- `lock` (Boolean) enable or disable locking
- `lock_ttl` (Integer) lock expiry in seconds
- `lock_client` Redis client for custom locking
- `store` ActiveSupport cache store (defaults to `Rails.cache` when available)

## Notes
- During the SWR window, stale values are served while a refresh runs.
- `refresh: :async` uses a background thread; choose `:sync` for deterministic refresh.
- When `lock` is enabled, the store must expose `redis` or you must provide `lock_client`.

## Release
```bash
bundle exec rake release
```
