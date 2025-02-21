# frozen_string_literal: true

require_relative "lib/trilogy_adapter/version"

Gem::Specification.new do |spec|
  spec.name = "activerecord-trilogy-adapter"
  spec.version = TrilogyAdapter::VERSION
  spec.platform = Gem::Platform::RUBY
  spec.authors = ["GitHub Engineering"]
  spec.email = ["opensource+trilogy@github.com"]
  spec.homepage = "https://github.com/trilogy-libraries/activerecord-trilogy-adapter"
  spec.summary = "Active Record adapter for https://github.com/trilogy-libraries/trilogy."
  spec.description = <<~EOF
    This gem is only needed before Rails 7.1, where the trilogy adapter is built in. 
    When you upgrade to a version after 7.1.a, replace this with `gem "trilogy"` to ensure
    that trilogy itself is available.
  EOF
  spec.license = "MIT"

  spec.metadata = {
    "source_code_uri" => "https://github.com/trilogy-libraries/activerecord-trilogy-adapter",
    "changelog_uri" => "https://github.com/trilogy-libraries/activerecord-trilogy-adapter/blob/master/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/trilogy-libraries/activerecord-trilogy-adapter/issues"
  }

  spec.add_dependency "trilogy", ">= 2.4.0"
  spec.add_dependency "activerecord", [">= 6.0.a", "< 7.1.a"]
  spec.add_development_dependency "minitest", "~> 5.11"
  spec.add_development_dependency "minitest-focus", "~> 1.1"
  spec.add_development_dependency "pry", "~> 0.10"
  spec.add_development_dependency "rake", "~> 12.3"

  spec.files = Dir["lib/**/*"]
  spec.extra_rdoc_files = Dir["README*", "LICENSE*"]
  spec.require_paths = ["lib"]
end
