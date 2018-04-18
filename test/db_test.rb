require 'helper'

class DbTest < Test::Unit::TestCase
  class << self
    def startup
      storages = []
      storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1')
      storages << FC::Storage.new(:name => 'rec1-sdb', :host => 'rec1')
      storages << FC::Storage.new(:name => 'rec1-sdc', :host => 'rec1')
      storages << FC::Storage.new(:name => 'rec1-sdd', :host => 'rec1')
      storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2')
      storages << FC::Storage.new(:name => 'rec2-sdb', :host => 'rec2')
      storages << FC::Storage.new(:name => 'rec2-sdc', :host => 'rec2')
      storages << FC::Storage.new(:name => 'rec2-sdd', :host => 'rec2')
      @@storages_ids = storages.map{|storage| storage.save; storage.id }

      policies = []
      policies << FC::Policy.new(:create_storages => 'rec1-sda,rec1-sdd', :copies => 2, :name => 'policy 1')
      policies << FC::Policy.new(:create_storages => 'rec1-sda,bla,rec2-sdd', :copies => 3, :name => 'policy 2')
      policies << FC::Policy.new(:create_storages => 'bla,rec1-sda,test', :copies => 4, :name => 'policy 3')
      @@policies_ids = policies.map{|policy| policy.save; policy.id }

      items = []
      items << FC::Item.new(:name => 'test1', :policy_id => policies.first.id, :size => 150)
      items << FC::Item.new(:name => 'test2', :policy_id => policies.first.id, :size => 200)
      items << FC::Item.new(:name => 'test3', :policy_id => policies.first.id, :size => 400)
      @@items_ids = items.map{|item| item.save; item.id }

      item_storages = []
      items.each do |item|
        item_storages << FC::ItemStorage.new(:item_id => item.id, :storage_name => 'rec1-sda')
        item_storages << FC::ItemStorage.new(:item_id => item.id, :storage_name => 'rec2-sda')
      end
      @@item_storages_ids = item_storages.map{|is| is.save; is.id }
    end
    def shutdown
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
    end
  end
  def setup
    @storages = @@storages_ids.map{|id| FC::Storage.find(id)}
    @storage = @storages.first
    @policies = @@policies_ids.map{|id| FC::Policy.find(id)}
    @policy = @policies.first
    @items = @@items_ids.map{|id| FC::Item.find(id)}
    @item = @items.first
    @item_storages = @@item_storages_ids.map{|id| FC::ItemStorage.find(id)}
    @item_storage = @item_storages.first
    @item_storage2 = @item_storages[1]
  end

  should 'sql logger' do
    FC::DB.logger = mock
    FC::DB.logger.expects(:debug).at_least_once
    FC::DB.query 'SELECT 1'
    FC::DB.logger = nil
  end

  should 'close, reconnect and connect_by_yml' do
    db_config_file = File.expand_path(File.dirname(__FILE__)) + '/db_test.yml'
    File.open(db_config_file, 'w') do |f|
      f.write(FC::DB.options.to_yaml)
    end

    connect = FC::DB.connect
    FC::DB.close
    assert_false connect.ping, 'Mysql2 connect not closed after close call'
    assert_nil FC::DB.connect, 'FC::DB.connect is not empty after close call'

    FC::DB.stubs(:options_yml_path).returns(db_config_file)
    FC::DB.connect_by_yml('test' => 'test')
    assert_true FC::DB.connect.ping, 'Not connected after connect_by_yml'
    assert_equal FC::DB.options[:test], 'test', 'options keys is not symbolized'

    FC::DB.close
    FC::DB.reconnect
    assert_true FC::DB.connect.ping, 'Not connected after reconnect'
  end

  should 'lazy_connect' do
    FC::DB.close
    FC::DB.lazy_connect do
      Mysql2::Client.new(FC::DB.options)
    end
    FC::DB.connect!(:multi_threads => true)
    assert_true FC::DB.connect.ping, 'Not connected after lazy_connect with Mysql2'
    assert_true FC::DB.options[:multi_threads], 'Options from connect!(options) was not setted'

    FC::DB.close
    FC::DB.lazy_connect do
      FC::DB.connect_by_config(FC::DB.options)
    end
    assert_true FC::DB.connect.ping, 'Not connected after lazy_connect with FC::DB.connect_by_config'
  end

  should 'multi threads' do
    FC::DB.connect!(:multi_threads => true)
    threads = Array.new(5) do
      Thread.new do
        assert_nothing_raised { FC::DB.query('select sleep(0.05)') }
      end
    end
    threads.each(&:join)
    assert_equal FC::DB.instance_variable_get(:@connects).keys.count, 6
    FC::DB.connect!(:multi_threads => false)
  end

  should 'mysql errors' do
    FC::DB.connect!(:reconnect => true)
    FC::DB.logger = mock
    FC::DB.logger.expects(:info).at_least_once
    assert_raise(Mysql2::Error) { FC::DB.query('retertert') }
    assert_raise(RuntimeError) { FC::DB.query('select ewrwerwerwer()') }
    FC::DB.connect!(:reconnect => false)
    FC::DB.logger = nil
  end

  should "items" do
    assert @items.count > 0, 'Items not loaded'
    @items.each{|item| assert item.time > 0, "Item (id=#{item.id}) time = 0"}
    sleep 1
    time = @item.time
    @item.tag = 'blabla'
    @item.save
    @item.reload
    assert_not_equal time, @item.time, "Item (id=#{@item.id}) time not changed after save"
    item2 = FC::Item.new(:name => @item.name, :policy_id => @item.policy_id)
    item2.save
    assert_equal 0, item2.id, "Item (id=#{item2.id}) successfull insert on uniq key"
  end

  should "storages" do
    assert @storages.count > 0, 'Storages not loaded'
    storage = FC::Storage.new(:name => 'rec1-sda', :host => 'rec1')
    storage.save
    assert_equal storage.id, 0, "Storage duplicate name"
  end

  should "policies and storages" do
    assert @policies.count > 0, 'Policies not loaded'
    assert_equal 'rec1-sda,rec1-sdd', @policies[0].create_storages, "Policy (id=#{@policies[0].id}) incorrect create_storages"
    assert_equal 'rec1-sda,rec2-sdd', @policies[1].create_storages, "Policy (id=#{@policies[0].id}) incorrect create_storages"
    assert_equal 'rec1-sda', @policies[2].create_storages, "Policy (id=#{@policies[0].id}) incorrect create_storages"

    FC::Policy.new(:create_storages => 'rec2-sda,rec2-sdd', :name => 'policy 1').save
    assert_equal 'rec1-sda,rec1-sdd', FC::Policy.where('name = ?', 'policy 1').first.create_storages, "Create policy with uniq name"
    FC::Policy.new(:create_storages => 'bla,test', :name => 'new policy').save  rescue nil # nil from mysql 5.6
    assert_nil FC::Policy.where('name = ?', 'new policy').first, "Create policy with incorrect create_storages"

    assert_raise(Mysql2::Error, 'Change storage name with linked polices') { @storages[0].name = 'blabla'; @storages[0].save }
    assert_raise(Mysql2::Error, 'Delete storage name with linked polices') { @storages[0].delete }
    assert_nothing_raised { @storages[6].name = 'rec2-sdc-new'; @storages[6].save }
    @storages[3].name = 'rec1-sdd-new' #rec1-sdd
    @storages[3].save
    @policies[0].reload
    @policies[1].reload
    assert_equal 'rec1-sda', @policies[0].create_storages, "Policy (id=#{@policies[0].id}) incorrect create_storages after storage change"
    @storages[7].delete  #rec2-sdd
    @@storages_ids.delete(@storages[7].id)
    @policies[0].reload
    @policies[1].reload
    assert_equal 'rec1-sda', @policies[1].create_storages, "Policy (id=#{@policies[1].id}) incorrect create_storages after storage delete"
    @policies[0].create_storages = 'rec2-sda,rec1-sda,bla bla'
    @policies[0].save
    @policies[0].reload
    assert_equal 'rec2-sda,rec1-sda', @policies[0].create_storages, "Policy (id=#{@policies[0].id}) incorrect create_storages after change"
    assert_raise(Mysql2::Error, 'Save empty policy storage') { @policies[0].create_storages = 'blabla'; @policies[0].save }
  end

  should "item_storages doubles" do
    is = FC::ItemStorage.new(:item_id => @item_storage.item_id, :storage_name => @item_storage.storage_name)
    is.save
    assert_equal 0, is.id, 'Item_storages successfull insert on uniq key'
  end

  should "item_storages times" do
    assert @item_storages.count > 0, 'Item_storages not loaded'
    @item_storages.each{|is| assert is.time > 0, "Item_storage (id=#{is.id}) time = 0"}
    sleep 1
    storage_name = @item_storage.storage_name
    time = @item_storage.time
    @item_storage.storage_name = 'rec1-sdc'
    @item_storage.save
    @item_storage.reload
    assert_not_equal time, @item_storage.time, "Item_storage (id=#{@item_storage.id}) time not changed after save"
    @item_storage.storage_name = storage_name
    @item_storage.save
  end

  should "item_storages references" do
    assert_raise(Mysql2::Error, "Delete item (id=#{@items[2].id} with references to item_storages") { @items[2].delete }
    assert_raise(Mysql2::Error, "Delete storage (id=#{@storages[4].id} with references to item_storages") { @storages[4].delete }
  end

  should "item_storages copies, statuses, size" do
    @items.each{|item| assert_equal 2, item.copies, "Item (id=#{item.id}) copies not inc after add item_storage"}
    size_sum = @items.inject(0){|sum, item| sum+item.size}
    assert_equal size_sum, @storage.size, "storage (id=#{@storage.id}) size <> ready not inc after item_storage.status='ready'"

    assert_equal 'new', @item.status, "Item (id=#{@item.id}) status <> 'new'"
    @item_storage.status = 'ready'
    @item_storage.save
    @item_storage2.status = 'ready'
    @item_storage2.save
    @item.reload
    assert_equal 'ready', @item.status, "Item (id=#{@item.id}) status <> 'ready' not changed after item_storage.status='ready'"
    @item_storage.status = 'error'
    @item_storage.save
    @item.reload
    assert_equal 'ready', @item.status, "Item (id=#{@item.id}) status <> 'ready' changed after one of two item_storage.status='error'"
    @item_storage2.status = 'error'
    @item_storage2.save
    @item.reload
    assert_equal 'error', @item.status, "Item (id=#{@item.id}) status <> 'error' not changed after item_storage.status='error'"
    assert_equal 2, @item.copies, "Item (id=#{@item.id}) copies changed after item_storage.status='error'"

    @item_storage.status = 'ready'
    @item_storage.save
    @item.reload
    assert_equal 'ready', @item.status, "Item (id=#{@item.id}) status <> 'ready' not changed after item_storage.status='ready'"
    @item_storage.status = 'delete'
    @item_storage.save
    @item.reload
    assert_equal 'error', @item.status, "Item (id=#{@item.id}) status <> 'error' not changed after item_storage.status='delete'"
    assert_equal 1, @item.copies, "Item (id=#{@item.id}) copies not decreased after item_storage.status='delete'"

    @item_storage.status = 'ready'
    @item_storage.save
    @item_storage2.status = 'ready'
    @item_storage2.save
    @item.reload
    assert_equal 'ready', @item.status, "Item (id=#{@item.id}) status <> 'ready' not changed after delete item_storage"
    @item_storage.delete
    @@item_storages_ids.delete(@item_storage.id)
    @item.reload
    @storage.reload
    assert_equal 'ready', @item.status, "Item (id=#{@item.id}) status <> 'ready' changed after delete item_storage"
    size_sum -= @item.size
    assert_equal size_sum, @storage.size, "storage (id=#{@storage.id}) size not dec after delete item_storage"
    @item_storage2.delete
    @@item_storages_ids.delete(@item_storage2.id)
    @item.reload
    assert_equal 'error', @item.status, "Item (id=#{@item.id}) status <> 'error' not changed after delete all item_storage"
  end

  should "errors time" do
    error = FC::Error.new(:message => 'test error')
    error.save
    error.reload
    assert error.time > 0, "Error (id=#{error.id}) time = 0"
  end
end
