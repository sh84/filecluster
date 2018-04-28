$:.unshift File.expand_path('../lib', File.dirname(__FILE__))

require 'ostruct'
require "test/unit"
require "shoulda-context"
require "filecluster"
require "mocha/setup"
require "byebug"

TEST_DATABASE = 'fc_test'
TEST_USER     = 'root'
TEST_PASSWORD = ''
# $MYSQL_HOST -u $MYSQL_USER -p $MYSQL_PASSWORD -d $MYSQL_DATABASE
FC::DB.connect_by_config(:username =>  TEST_USER,    :password => TEST_PASSWORD, :host => ENV['MYSQL_HOST'] )
FC::DB.query("DROP DATABASE IF EXISTS #{TEST_DATABASE}")
FC::DB.query("CREATE DATABASE #{TEST_DATABASE}")
FC::DB.query("USE #{TEST_DATABASE}")
FC::DB.init_db(true)
FC::DB.options[:database] = TEST_DATABASE


def ssh_hostname
  ENV['SSH_HOST'] || 'localhost'
end
