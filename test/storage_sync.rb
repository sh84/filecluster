require 'helper'
require 'manage'

class DaemonTest < Test::Unit::TestCase
  class << self
    def startup
      # tmp fake storage dir
      `rm -rf /tmp/host*-sd*`
      `mkdir -p /tmp/host1-sda/`
      
      # test files to copy
      @@test_file_path = '/tmp/fc_test_file'
      `dd if=/dev/urandom of=#{@@test_file_path} bs=1M count=1 2>&1`
      
      @@storage = FC::Storage.new(:name => 'host1-sda', :host => 'host1', :path => '/tmp/host1-sda/', :copy_id => 1, :size_limit => 1000000000, :check_time => Time.new.to_i)
      @@storage.save
      @@policy = FC::Policy.new(:create_storages => 'host1-sda', :copy_storages => 'host1-sda', :copies => 1, :name => 'policy 1')
      @@policy.save
    end
    
    def shutdown
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
      `rm -rf /tmp/host*-sd*`
      `rm -rf #{@@test_file_path}`
    end
  end
  
  def setup
    FC::Storage.any_instance.stubs(:host).returns('host1')
    FC::Storage.stubs(:curr_host).returns('host1')
  end
  
  should "sync_all" do
    assert_nothing_raised { @item1 = FC::Item.create_from_local(@@test_file_path, 'a/test1', @@policy, {:tag => 'test'}) }
    assert_nothing_raised { @item2 = FC::Item.create_from_local(@@test_file_path, 'a/b/test2', @@policy, {:tag => 'test'}) }
    assert_nothing_raised { @item3 = FC::Item.create_from_local(@@test_file_path, 'a/b/c/test3', @@policy, {:tag => 'test'}) }
    assert_nothing_raised { @item4 = FC::Item.create_from_local(@@test_file_path, 'a/b/c/d/test4', @@policy, {:tag => 'test'}) }
    `mv /tmp/host1-sda/a/test1 /tmp/host1-sda/test1`
    `mv /tmp/host1-sda/a/b/c/d/test4 /tmp/host1-sda/a/b/c/d/test5`
    `mkdir /tmp/host1-sda/test_dir`
    `cp #{@@test_file_path} /tmp/host1-sda/test_dir/t1`
    `cp #{@@test_file_path} /tmp/host1-sda/test_dir/t2`
    
    make_storages_sync(@@storage, true, true)
    
    @item1.reload
    @item2.reload
    @item3.reload
    @item4.reload
    assert_equal 'error', @item1.status
    assert_equal 'ready', @item2.status
    assert_equal 'ready', @item3.status
    assert_equal 'error', @item4.status
    size = `du -sb #{@@test_file_path} 2>&1`.to_i
    assert_equal 0, `du -sb /tmp/host1-sda/test1 2>&1`.to_i
    assert_equal size, `du -sb /tmp/host1-sda/a/b/test2 2>&1`.to_i
    assert_equal size, `du -sb /tmp/host1-sda/a/b/c/test3 2>&1`.to_i
    assert_equal 0, `du -sb /tmp/host1-sda/a/b/c/d/test5 2>&1`.to_i
    assert_equal 0, `du -sb /tmp/host1-sda/a/b/c/d 2>&1`.to_i
    assert_equal 0, `du -sb tmp/host1-sda/test_dir 2>&1`.to_i
  end
end