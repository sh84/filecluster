require 'rubygems'
$:.unshift File.expand_path('../lib', File.dirname(__FILE__))

begin
  gem 'minitest', '~> 5'
rescue Gem::LoadError
  puts "Gem minitest has old version! Run bundle install."
  exit
end

require "minitest/autorun"
require "minitest/great_expectations"
require "filecluster"
require "mocha/setup"

TEST_DATABASE = 'fc_test'
TEST_USER     = 'root'
TEST_PASSWORD = ''

FC::DB.connect_by_config(:username => TEST_USER, :password => TEST_PASSWORD)
FC::DB.query("DROP DATABASE IF EXISTS #{TEST_DATABASE}")
FC::DB.query("CREATE DATABASE #{TEST_DATABASE}")
FC::DB.query("USE #{TEST_DATABASE}")
FC::DB.init_db(true)
FC::DB.options[:database] = TEST_DATABASE

class FC::TestCase < Minitest::Test
  def sql_debug(&block)
    old_query = FC::DB.method(:query)
    FC::DB.define_singleton_method(:query) do |sql|
      puts ">> #{sql}"
      old_query.call(sql)
    end
    block.call
    FC::DB.define_singleton_method(:query, old_query)
  end
  
  def field_time_test(el)
    assert el.respond_to?(:time), "#{el.class}: no time field"
    el.reload
    assert time = el.time, "#{el.class}: no time after save"
    sleep 1
    el.save!
    el.reload
    assert el.time > time, "#{el.class}: no time after save"
  end
end