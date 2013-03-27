require 'helper'

class FunctionalTest < Test::Unit::TestCase 
    class << self
    def startup
      # tmp fake storages dirs
      `mkdir -p /tmp/host1-sda/`
      `mkdir -p /tmp/host1-sdb/`
      `mkdir -p /tmp/host2-sda/`
      `mkdir -p /tmp/host2-sdb/`
      
      # test file to copy
      @@test_file_path = '/tmp/fc_test_file'
      `dd if=/dev/urandom of=#{@@test_file_path} bs=100K count=1 2>&1`
      
      FC::Storage.any_instance.stubs(:host).returns('localhost')
      FC::Storage.stubs(:curr_host).returns('localhost')
      @@storages = []
      @@storages << FC::Storage.new(:name => 'host1-sda', :host => 'host1', :path => '/tmp/host1-sda/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host1-sdb', :host => 'host1', :path => '/tmp/host1-sdb/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host2-sda', :host => 'host2', :path => '/tmp/host2-sda/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host2-sdb', :host => 'host2', :path => '/tmp/host2-sdb/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages.each { |storage| storage.save}
      
      @@policy = FC::Policy.new(:storages => 'host1-sda,host2-sda,host1-sdb,host2-sdb', :copies => 2)
      @@policy.save
    end
    def shutdown_
      FC::DB.connect.query("DELETE FROM items_storages")
      FC::DB.connect.query("DELETE FROM items")
      FC::DB.connect.query("DELETE FROM policies")
      FC::DB.connect.query("DELETE FROM storages")
      Dir.rmdir('/tmp/host1-sda/')
      Dir.rmdir('/tmp/host1-sdb/')
      Dir.rmdir('/tmp/host2-sda/')
      Dir.rmdir('/tmp/host2-sdb/')
    end
  end
  
  def setup
    
  end
  
  should "item create_from_local" do
    item = FC::Item.create_from_local(@@test_file_path, 'test1', @@policy, {:tag => 'test'})
    puts item
  end
  
end
