#!/usr/bin/env rake
require "bundler/gem_tasks"
require 'rake/clean'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList["test/*_test.rb"]
end

task :default => :post_install
task :post_install do
  
end