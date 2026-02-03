# Cache SWR

Server-side stale-while-revalidate caching for Rails.

## Install
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

## Notes
- During the SWR window, stale values are served while a refresh runs.
- Refresh can run in a background thread (`refresh: :async`) or inline (`refresh: :sync`).
- By default, locking expects a Redis-backed store that exposes `redis`. Use `lock: false` for local in-memory use.

## Release
```bash
bundle exec rake release
```
