# frozen_string_literal: true

source "https://rubygems.org"

if !ENV["RAILS_VERSION"]
  gem "activerecord"
else
  gem "activerecord", ENV["RAILS_VERSION"]
end

gem "trilogy"

gemspec

# Separately require this due to concurrent_ruby 1.3.5 and later removing the
# dependency to logger
require "logger"
