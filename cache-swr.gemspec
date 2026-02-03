# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "cache/swr/version"

Gem::Specification.new do |spec|
  spec.name = "cache-swr"
  spec.version = Cache::SWR::VERSION
  spec.authors = ["MounirGaiby"]
  spec.email = ["mounirgaiby@gmail.com"]

  spec.summary = "Stale-while-revalidate caching for Rails with background refresh."
  spec.description = "Serve stale cached values while recomputing in the background to reduce tail latency."
  spec.homepage = "https://github.com/elysium-arc/cache-swr"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/elysium-arc/cache-swr"
  spec.metadata["changelog_uri"] = "https://github.com/elysium-arc/cache-swr/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 6.1"
  spec.add_dependency "redis", ">= 4.0"

  spec.add_development_dependency "bundler", ">= 1.17"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
