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
      @@storages << FC::Storage.new(:name => 'host3-sda', :host => 'host3', :path => '/tmp/host3-sda/', :size_limit => 1000000)
      @@storages.each { |storage| storage.save}
      
      @@policies = []
      @@policies << FC::Policy.new(:storages => 'host1-sda,host2-sda', :copies => 2)
      @@policies << FC::Policy.new(:storages => 'host1-sdb,host2-sdb', :copies => 2)
      @@policies << FC::Policy.new(:storages => 'host3-sda', :copies => 1)
      @@policies << FC::Policy.new(:storages => 'host2-sda', :copies => 1)
      @@policies.each { |policy| policy.save}
    end
    def shutdown
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
  
  should "item create_from_local error local path" do
    errors_count = FC::Error.where.count
    assert_raise(RuntimeError) { FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[1], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.where.count, "Error not saved after error local path"
  end
  
  should "item create_from_local replace" do
    @item  = FC::Item.new(:name => 'test2', :policy_id => @@policies[0].id)
    @item.save
    errors_count = FC::Error.where.count
    assert_raise(RuntimeError, "replace item") { FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[0], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.where.count, "Error not saved after replace item"
    assert_nothing_raised { @item2 = FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[0], {:replace => true, :tag => 'test'}) }
    assert_equal @item.id, @item2.id, "Item (id1=#{@item.id}, id2=#{@item2.id}) change id after replace"
  end
  
  should "item create_from_local available storage" do
    errors_count = FC::Error.where.count
    assert_raise(RuntimeError, "available storage") { FC::Item.create_from_local(@@test_file_path, 'test3', @@policies[2], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.where.count, "Error not saved on available storage"
  end
  
  should "item create_from_local delete item_storage" do
    @item  = FC::Item.new(:name => 'test4', :policy_id => @@policies[3].id)
    @item.save
    item_storage = FC::ItemStorage.new(:item_id => @item.id, :storage_name => 'host2-sda')
    item_storage.save
    assert_nothing_raised { @item = FC::Item.create_from_local(@@test_file_path, 'test4', @@policies[3], {:tag => 'test', :replace => true}) }
    item_storages = @item.get_item_storages
    assert_equal 1, item_storages.count
    assert_not_equal item_storage.id, item_storages.first.id
    assert_raise(RuntimeError) { item_storage.reload }
  end
  
  should "item create_from_local check size" do
    FC::Storage.any_instance.stubs(:copy_path => true, :file_size => 10)
    errors_count = FC::Error.where.count
    assert_raise(RuntimeError) { FC::Item.create_from_local(@@test_file_path, 'test5', @@policies[1], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.where.count, "Error not saved after check size" 
  end
  
  should "item create_from_local inplace" do
    tmp_file_path = "/tmp/host2-sda/inplace_test"
    `cp #{@@test_file_path} #{tmp_file_path}`
    assert_nothing_raised { @item = FC::Item.create_from_local(tmp_file_path, 'inplace_test', @@policies[0]) }
  end
end
