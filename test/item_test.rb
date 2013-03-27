require 'helper'

class ItemTest < Test::Unit::TestCase
  class << self
    def startup
      @@item = FC::Item.new(:name => 'test item', :policy_id => 1, :size => 150)
      @@item.save
      
      @@storages = []
      @@item_storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1')
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2')
      @@item_storages.each do |storage|
        storage.save
        item_storage = FC::ItemStorage.new(:item_id => @@item.id, :storage_name => storage.name)
        item_storage.save
        @@item_storages << item_storage
      end
    end
    def shutdown
      FC::DB.connect.query("DELETE FROM items_storages")
      FC::DB.connect.query("DELETE FROM items")
    end
  end 

  should "get_item_storages" do
    assert_same_elements @@item_storages.map(&:id), @@item.get_item_storages.map(&:id)
  end
  
  should "create_from_local" do
    policy = FC::Policy.new
    assert_raise(ArgumentError) { FC::Item.create_from_local }
    assert_raise(ArgumentError) { FC::Item.create_from_local '/bla/bla' }
    assert_raise(ArgumentError) { FC::Item.create_from_local '/bla/bla', 'test' }
    assert_raise(RuntimeError) { FC::Item.create_from_local '/bla/bla', 'test', {}}
    assert_raise(RuntimeError) { FC::Item.create_from_local '/bla/bla/bla', 'test', policy}
  end
  
end
