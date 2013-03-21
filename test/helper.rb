$:.unshift File.expand_path('../lib', File.dirname(__FILE__))

require "test/unit"
require "shoulda-context"
require "mocha/setup"
require "filecluster"

TEST_DATABASE = 'fc_test'
TEST_USER     = 'root'
TEST_PASSWORD = ''

FC::DB.connect_by_config(:username => TEST_USER, :password => TEST_PASSWORD)
FC::DB.connect.query("DROP DATABASE IF EXISTS #{TEST_DATABASE}")
FC::DB.connect.query("CREATE DATABASE #{TEST_DATABASE}")
FC::DB.connect.query("USE #{TEST_DATABASE}")
FC::DB.init_db
