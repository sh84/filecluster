require 'helper'

class FunctionalTest < Test::Unit::TestCase 
    class << self
    def startup
      # tmp fake storages dirs
      `rm -rf /tmp/host*-sd*`
      `mkdir -p /tmp/host1-sda/ /tmp/host2-sda/`
      
      # test file to copy
      @@test_file_path = '/tmp/fc_test_file'
      `dd if=/dev/urandom of=#{@@test_file_path} bs=100K count=1 2>&1`
      
      @@storages = []
      @@storages << FC::Storage.new(:name => 'host1-sda', :host => 'host1', :path => '/tmp/host1-sda/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host1-sdb', :host => 'host1', :path => '/tmp/host1-sdb/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host2-sda', :host => 'host2', :path => '/tmp/host2-sda/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host2-sdb', :host => 'host2', :path => '/tmp/host2-sdb/', :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages.each { |storage| storage.save}
      
      @@policies = []
      @@policies << FC::Policy.new(:storages => 'host1-sda,host2-sda', :copies => 2)
      @@policies << FC::Policy.new(:storages => 'host1-sdb,host2-sdb', :copies => 2)
      @@policies.each { |policy| policy.save}
    end
    def shutdown1
      FC::DB.connect.query("DELETE FROM items_storages")
      FC::DB.connect.query("DELETE FROM items")
      FC::DB.connect.query("DELETE FROM policies")
      FC::DB.connect.query("DELETE FROM storages")
      `rm -rf /tmp/host1-sda /tmp/host2-sda`
    end
  end
  
  def setup
    FC::Storage.any_instance.stubs(:host).returns('localhost')
    FC::Storage.stubs(:curr_host).returns('localhost')
  end
  
  should "item create_from_local successful" do
    assert_nothing_raised { @item = FC::Item.create_from_local(@@test_file_path, 'test1', @@policies[0], {:tag => 'test'}) }
    assert_kind_of FC::Item, @item
    assert_equal `du -b /tmp/host1-sda/test1 2>&1`.to_i, `du -b #{@@test_file_path} 2>&1`.to_i
    assert_equal `du -b /tmp/host1-sda/test1 2>&1`.to_i, @item.size
    assert_equal 'ready', @item.status
    item_storages = @item.get_item_storages
    assert_equal 1, item_storages.count
    item_storage = item_storages.first
    assert_equal 'ready', item_storage.status
    assert_equal 'host1-sda', item_storage.storage_name
  end
  
  should "item create_from_local error path" do
    assert_raise(RuntimeError) { FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[1], {:tag => 'test'}) } 
  end
end
