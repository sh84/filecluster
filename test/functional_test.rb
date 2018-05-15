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
    FC::Storage.any_instance.stubs(:host).returns(ssh_hostname)
    FC::Storage.stubs(:curr_host).returns(ssh_hostname)
  end

  def stub_method(obj, method, method_impl)
    obj.singleton_class.send(:alias_method, "#{method}_mock_backup", method)
    obj.define_singleton_method(method, method_impl)
    yield if block_given?
    obj.singleton_class.send(:alias_method, method, "#{method}_mock_backup")
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
    @item = FC::Item.new(:name => 'test2', :policy_id => @@policies[3].id)
    @item.save
    errors_count = FC::Error.where.count
    assert_raise(RuntimeError, "replace item") { FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[3], {:tag => 'test'}) }
    assert_equal errors_count+1, FC::Error.where.count, "Error not saved after replace item"
    assert_nothing_raised { @item2 = FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[3], {:replace => true, :tag => 'test'}) }
    assert_equal @item.id, @item2.id, "Item (id1=#{@item.id}, id2=#{@item2.id}) change id after replace"
    item_storage = @item2.get_item_storages.first
    item_storage.storage_name = 'host1-sdb'
    item_storage.save
    assert_nothing_raised { @item2 = FC::Item.create_from_local(@@test_file_path, 'test2', @@policies[3], {:replace => true, :tag => 'test'}) }
    item_storages = Hash[*@item2.get_item_storages.map { |el| [el.storage_name, el] }.flatten]
    assert_same_elements item_storages.keys, ['host1-sdb', 'host2-sda']
    assert_equal 'delete', item_storages['host1-sdb'].status
    assert_equal 'ready', item_storages['host2-sda'].status
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

  should "item create_from_local check md5" do
    errors_count = FC::Error.where.count
    @item = FC::Item.create_from_local(@@test_file_path, 'test5', @@policies[0], {:tag => 'test'})
    assert @item.md5
    item_storage = @item.make_item_storage(@@storages[0], 'copy')
    # rewrite item file
    `dd if=/dev/urandom of=#{@@storages[0].path}#{@item.name} bs=100K count=1 2>&1`
    # md5 check must fail on copy
    assert_raise(RuntimeError) { @item.copy_item_storage(@@storages[0], @@storages[1], item_storage) }
    assert_equal errors_count+1, FC::Error.where.count, "Error not saved after check md5"
  end

  should 'item create_from_local disables md5 check' do
    @item = FC::Item.create_from_local(@@test_file_path, 'test7', @@policies[0], {:tag => 'test', :no_md5 => true})
    assert_nil @item.md5
    item_storage = @item.make_item_storage(@@storages[0], 'copy')
    # rewrite item file
    `dd if=/dev/urandom of=#{@@storages[0].path}#{@item.name} bs=100K count=1 2>&1`
    # no md5 check on copy - success
    assert_nothing_raised { @item.copy_item_storage(@@storages[0], @@storages[1], item_storage) }
  end

  should 'item keep deferred_delete after copy' do
    @item = FC::Item.create_from_local(@@test_file_path, 'test9', @@policies[0], {:tag => 'test', :no_md5 => true})
    item_storage = @item.make_item_storage(@@storages[1], 'copy')
    @item.mark_deleted
    # rewrite item file
    `dd if=/dev/urandom of=#{@@storages[0].path}#{@item.name} bs=100K count=1 2>&1`
    @item.copy_item_storage(@@storages[0], @@storages[1], item_storage)
    @item.reload
    assert_equal 2, @item.get_item_storages.size
    @item.get_item_storages.each do |is|
      assert_equal 'ready', is.status
    end
    assert_equal 'deferred_delete', @item.status
  end

  should 'item keep deferred_delete status if changed during copy' do
    @item = FC::Item.create_from_local(@@test_file_path, 'test10', @@policies[0], {:tag => 'test', :no_md5 => true})
    item_storage = @item.make_item_storage(@@storages[1], 'copy')
    # rewrite item file
    `dd if=/dev/urandom of=#{@@storages[0].path}#{@item.name} bs=100K count=1 2>&1`
    # no md5 check on copy - success
    item = @item
    stubbed_method_impl = proc { |*args|
      copy_to_local_mock_backup(*args)
      item.mark_deleted
    }
    stub_method(@@storages[0], :copy_to_local, stubbed_method_impl) do
      @item.copy_item_storage(@@storages[0], @@storages[1], item_storage)
    end
    @item.reload
    assert_equal 'ready', item_storage.status
    assert_equal 'deferred_delete', @item.status
  end

  should 'item keep deferred_delete status if changed during copy and error was raised' do
    @item = FC::Item.create_from_local(@@test_file_path, 'test11', @@policies[0], {:tag => 'test'})
    item_storage = @item.make_item_storage(@@storages[1], 'copy')
    # rewrite item file
    `dd if=/dev/urandom of=#{@@storages[0].path}#{@item.name} bs=100K count=1 2>&1`

    # simulate mark_delete during copy process and raise exception
    item = @item
    stubbed_method_impl = proc { |*_|
      item.mark_deleted
      raise 'oops'
    }
    stub_method(@@storages[0], :copy_to_local, stubbed_method_impl) do
      assert_raise(RuntimeError) { @item.copy_item_storage(@@storages[0], @@storages[1], item_storage) }
    end
    @item.reload
    assert_equal 'error', item_storage.status
    assert_equal 'deferred_delete', @item.status
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

  should 'item create_from_local with block for choose storage' do
    item = FC::Item.create_from_local(@@test_file_path,
                                      '/bla/bla/test7',
                                      @@policies[0],
                                      :tag => 'test') do |storages|
      storages.select { |s| s.name == 'host2-sda' }
    end
    assert_kind_of FC::Item, item

    assert_equal `du -sb /tmp/host2-sda/bla/bla/test7 2>&1`.to_i, item.size
    assert_equal 'ready', item.status
    item_storages = item.get_item_storages
    assert_equal 1, item_storages.count
    assert_equal 'ready', item_storages.first.status
    assert_equal 'host2-sda', item_storages.first.storage_name
    item = FC::Item.create_from_local(@@test_file_path,
                                      '/bla/bla/test8',
                                      @@policies[0],
                                      :tag => 'test') { [@@storages[4]] }
    assert_equal 'host3-sda', item.get_item_storages.first.storage_name
  end
end
