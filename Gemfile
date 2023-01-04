# frozen_string_literal: true

source "https://rubygems.org"

if !ENV["RAILS_VERSION"] || ENV["RAILS_VERSION"] == "main"
  gem "activerecord", git: "https://github.com/rails/rails", branch: "main"
else
  gem "activerecord", ENV["RAILS_VERSION"]
end

gemspec
