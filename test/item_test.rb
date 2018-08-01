require 'helper'

class ItemTest < Test::Unit::TestCase
  class << self
    def startup
      @@item = FC::Item.new(:name => '/test item', :policy_id => 1, :size => 150)
      @@item.save
      
      @@storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1', :url => 'http://rec1/sda/')
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2', :url => 'http://rec2/sda/')
      @@item_storages = @@storages.map do |storage|
        storage.save
        item_storage = FC::ItemStorage.new(:item_id => @@item.id, :storage_name => storage.name, :status => 'ready')
        item_storage.save
        item_storage
      end
      @@storages << FC::Storage.new(:name => 'rec3-sda', :host => 'rec3', :url => 'http://rec3/sda/')
      @@storages[2].save
    end
    def shutdown
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM storages")
    end
  end
  
  setup do
    @@storages.each do |s|
      s.check_time = 0
      s.http_check_time = 0
      s.save
    end
  end

  should "create_from_local" do    policy = FC::Policy.new
    assert_raise(ArgumentError) { FC::Item.create_from_local }
    assert_raise(ArgumentError) { FC::Item.create_from_local '/bla/bla' }
    assert_raise(ArgumentError) { FC::Item.create_from_local '/bla/bla', 'test' }
    assert_raise(RuntimeError) { FC::Item.create_from_local '/bla/bla', 'test', {}}
    assert_raise() { FC::Item.create_from_local '/bla/bla/bla', 'test', policy}
  end
  
  should "immediate_delete" do
    @@item.immediate_delete
    @@item.reload
    assert_equal 'delete', @@item.status
    @@item_storages.each do |item_storage| 
      item_storage.reload
      assert_equal 'delete', item_storage.status
      item_storage.status = 'ready'
      item_storage.save
    end
    @@item.status = 'ready'
    @@item.save
  end

  should 'mark_deleted' do
    @@item.mark_deleted
    @@item.reload
    assert_equal 'deferred_delete', @@item.status
    @@item_storages.each do |item_storage| 
      item_storage.reload
      assert_equal 'ready', item_storage.status
    end
  end
  
  should "make_item_storage" do
    storage_size = @@storages[2].size.to_i
    assert_kind_of FC::ItemStorage, @@item.make_item_storage(@@storages[2])
    assert_equal storage_size+@@item.size, @@storages[2].size
  end
  
  should "get_item_storages" do
    assert_same_elements @@item_storages.map(&:id), @@item.get_item_storages.map(&:id)
  end
  
  should 'item get_available_storages' do
    @@storages[0].update_check_time
    assert_equal 1, @@item.get_available_storages.count
    assert_equal @@storages[0].name, @@item.get_available_storages.first.name
  end

  should 'item get_available_storages (http_up? influence)' do
    # all storages have http_up? == false
    storages = @@item_storages.map do |is|
      @@storages.detect { |s| s.name == is.storage_name }
    end.compact
    storages.each do |s|
      assert !s.http_up?
    end
    assert storages.size > 1
    storages.each(&:update_check_time)
    assert_equal storages.size, @@item.get_available_storages.count

    # set one storage http_up? == true
    storages[0].update_http_check_time
    assert storages[0].http_up?

    assert_equal 1, @@item.get_available_storages.count
    assert_equal storages[0].name, @@item.get_available_storages.first.name
    assert_equal 'http://rec1/sda/test item', @@item.url
  end

  should "item urls" do
    assert_equal 0, @@item.urls.count
    @@storages.each(&:update_check_time)
    assert_same_elements ["http://rec1/sda/test item", "http://rec2/sda/test item"], @@item.urls
  end
  
  should "item url by url_weight" do
    @@storages.each(&:update_check_time)
    @@storages.each{|s| s.url_weight = -1; s.save}
    assert_raise(RuntimeError) { @@item.url }
    
    @@storages[0].url_weight = 1
    @@storages[0].save
    assert_equal "http://rec1/sda/test item", @@item.url
    
    @@storages[1].url_weight = 2
    @@storages[1].save
    Kernel.stubs(:rand).returns(1)
    assert_equal "http://rec2/sda/test item", @@item.url
  end
end
