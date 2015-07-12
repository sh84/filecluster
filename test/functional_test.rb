require 'helper'

class FunctionalTest < Test::Unit::TestCase 
    class << self
    def startup
      # tmp fake storages dirs
      `rm -rf /tmp/host*-sd*`
      `mkdir -p /tmp/host1-sda/ /tmp/host2-sda/`
      
      # test file to copy
      @@test_file_path = '/tmp/fc test_file "~!@#$%^&*()_+|\';'
      `dd if=/dev/urandom of=#{@@test_file_path.shellescape} bs=100K count=1 2>&1`
      @@test_dir_path = '/tmp/fc test_dir'
      `mkdir -p #{@@test_dir_path.shellescape}/aaa #{@@test_dir_path.shellescape}/bbb`
      `cp #{@@test_file_path.shellescape} #{@@test_dir_path.shellescape}/aaa/test1`
      `cp #{@@test_file_path.shellescape} #{@@test_dir_path.shellescape}/bbb/test2`
      
      @@storages = []
      @@storages << FC::Storage.new(:name => 'host1-sda', :host => 'host1', :path => '/tmp/host1-sda/', :size => 0, :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host1-sdb', :host => 'host1', :path => '/tmp/host1-sdb/', :size => 0, :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host2-sda', :host => 'host2', :path => '/tmp/host2-sda/', :size => 10, :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host2-sdb', :host => 'host2', :path => '/tmp/host2-sdb/', :size => 10, :size_limit => 1000000, :check_time => Time.new.to_i)
      @@storages << FC::Storage.new(:name => 'host3-sda', :host => 'host3', :path => '/tmp/host3-sda/', :size => 100, :size_limit => 1000000)
      @@storages.each { |storage| storage.save}
      
      @@policies = []
      @@policies << FC::Policy.new(:create_storages => 'host1-sda,host2-sda', :copy_storages => 'host1-sdb', :copies => 2, :name => 'policy 1')
      @@policies << FC::Policy.new(:create_storages => 'host1-sdb,host2-sdb', :copy_storages => 'host1-sdb', :copies => 2, :name => 'policy 2')
      @@policies << FC::Policy.new(:create_storages => 'host3-sda', :copy_storages => 'host1-sdb', :copies => 1, :name => 'policy 3')
      @@policies << FC::Policy.new(:create_storages => 'host2-sda', :copy_storages => 'host1-sdb', :copies => 1, :name => 'policy 4')
      @@policies.each { |policy| policy.save}
    end
    def shutdown
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
      #`rm -rf /tmp/host*-sd*`
      #`rm -rf #{@@test_file_path.shellescape}`
      #`rm -rf #{@@test_dir_path.shellescape}`
    end
  end
  
  def setup
    FC::Storage.any_instance.stubs(:host).returns('localhost')
    FC::Storage.stubs(:curr_host).returns('localhost')
  end
  
  should "item create_from_local successful" do
    assert_nothing_raised { @item = FC::Item.create_from_local(@@test_file_path, '/bla/bla/test1', @@policies[0], {:tag => 'test'}) }
    assert_kind_of FC::Item, @item
    assert_equal `du -sb /tmp/host1-sda/bla/bla/test1 2>&1`.to_i, `du -sb #{@@test_file_path.shellescape} 2>&1`.to_i
    assert_equal `du -sb /tmp/host1-sda/bla/bla/test1 2>&1`.to_i, @item.size
    assert_equal 'ready', @item.status
    item_storages = @item.get_item_storages
    assert_equal 1, item_storages.count
    item_storage = item_storages.first
    assert_equal 'ready', item_storage.status
    assert_equal 'host1-sda', item_storage.storage_name
  end
  
  should "item create_from_local dir successful" do
    assert_nothing_raised { @item = FC::Item.create_from_local(@@test_dir_path, '/bla/bla/test_dir', @@policies[0], {:tag => 'test_dir'}) }
    assert_kind_of FC::Item, @item
    assert_equal true, @item.dir?
    assert_equal `du -sb /tmp/host1-sda/bla/bla/test_dir 2>&1`.to_i, `du -sb #{@@test_dir_path.shellescape} 2>&1`.to_i
    assert_equal `du -sb /tmp/host1-sda/bla/bla/test_dir 2>&1`.to_i, @item.size
    assert_equal 'ready', @item.status
    item_storages = @item.get_item_storages
    assert_equal 1, item_storages.count
    item_storage = item_storages.first
    assert_equal 'ready', item_storage.status
    assert_equal 'host1-sda', item_storage.storage_name
  end
  
  should "item create_from_local replace" do
    @item  = FC::Item.new(:name => 'test2', :policy_id => @@policies[0].id)
    @item.save
    errors_count = FC::Error.all.count
    assert_raise(RuntimeError, "replace item") { FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[0], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.all.count, "Error not saved after replace item"
    assert_nothing_raised { @item2 = FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[0], {:replace => true, :tag => 'test'}) }
    assert_equal @item.id, @item2.id, "Item (id1=#{@item.id}, id2=#{@item2.id}) change id after replace"
  end
  
  should "item create_from_local available storage" do
    errors_count = FC::Error.all.count
    assert_raise(RuntimeError, "available storage") { FC::Item.create_from_local(@@test_file_path, 'test3', @@policies[2], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.all.count, "Error not saved on available storage"
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
  
  should "item create_from_local check md5" do
    errors_count = FC::Error.all.count
    @item = FC::Item.create_from_local(@@test_file_path, 'test5', @@policies[0], {:tag => 'test'})
    item_storage = @item.make_item_storage(@@storages[0], status = 'copy')
    `dd if=/dev/urandom of=#{@@storages[0].path}#{@item.name} bs=100K count=1 2>&1`
    assert_raise(RuntimeError) { @item.copy_item_storage(@@storages[0], @@storages[1], item_storage) }
    assert_equal errors_count+1, FC::Error.all.count, "Error not saved after check md5"
  end
  
  should "item create_from_local inplace" do
    tmp_file_path = "/tmp/host2-sda/inplace test"
    `cp #{@@test_file_path.shellescape} #{tmp_file_path.shellescape}`
    assert_nothing_raised { FC::Item.create_from_local(tmp_file_path, 'inplace test', @@policies[0]) }
  end
  
  should "item create_from_local inplace for dir" do
    tmp_dir_path = "/tmp/host2-sda/inplace test dir/"
    `mkdir #{tmp_dir_path.shellescape}`
    `cp #{@@test_file_path.shellescape} #{tmp_dir_path.shellescape}`
    assert_nothing_raised { FC::Item.create_from_local(tmp_dir_path, '/inplace test dir/', @@policies[0]) }
  end
  
  should "item create_from_local with move and delete" do
    tmp_file_path = "/tmp/fc test file for delete"
    `cp #{@@test_file_path.shellescape} #{tmp_file_path.shellescape}`
    File.stubs(:delete).never
    assert_nothing_raised { @item = FC::Item.create_from_local(tmp_file_path, '/bla/bla/test6', @@policies[0], {:remove_local => true}) }
    assert_kind_of FC::Item, @item
    assert_equal `du -sb #{@@test_file_path.shellescape} 2>&1`.to_i, @item.size
    assert_equal 'ready', @item.status
    assert_equal false, File.exists?(tmp_file_path)
    File.unstub(:delete)
  end
end
