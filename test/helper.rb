$:.unshift File.expand_path('../lib', File.dirname(__FILE__))

require "test/unit"
require "shoulda-context"
require "filecluster"
require "mocha/setup"

TEST_DATABASE = 'fc_test'
TEST_USER     = 'root'
TEST_PASSWORD = ''

FC::DB.connect_by_config(:username => TEST_USER, :password => TEST_PASSWORD)
FC::DB.query("DROP DATABASE IF EXISTS #{TEST_DATABASE}")
FC::DB.query("CREATE DATABASE #{TEST_DATABASE}")
FC::DB.query("USE #{TEST_DATABASE}")
FC::DB.init_db
FC::DB.options[:database] = TEST_DATABASE
