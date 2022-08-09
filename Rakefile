# frozen_string_literal: true

begin
  require "bundler/gem_tasks"

  require "rake/testtask"

  Rake::TestTask.new do |task|
    task.libs << "test"
    task.pattern = "test/**/*_test.rb"
  end
rescue LoadError => error
  puts error.message
end

task default: %i[test]
