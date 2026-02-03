# frozen_string_literal: true

# :nocov:
begin
  require "rails/railtie"
rescue LoadError
end

if defined?(Rails::Railtie)
  module Cache
    module SWR
      module StoreExtension
        def fetch_swr(key, ttl:, swr:, **options, &block)
          Cache::SWR.fetch(key, ttl: ttl, swr: swr, store: self, **options, &block)
        end
      end

      class Railtie < Rails::Railtie
        initializer "cache_swr.extend_cache" do
          ActiveSupport.on_load(:active_support_cache) do
            ::ActiveSupport::Cache::Store.include(Cache::SWR::StoreExtension)
          end
        end
      end
    end
  end
end
# :nocov:
