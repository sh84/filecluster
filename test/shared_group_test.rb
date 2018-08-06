require 'helper'

class SharedGroupTest < Test::Unit::TestCase
  class << self
    def startup
      @@item = FC::Item.new(:name => '/test item', :policy_id => 1, :size => 150)
      @@item.save

      @@storages = []
      @@storages << FC::Storage.new(:name => 'write_storage-1', :host => 'w1', :url => 'http://writer-1/sda/', url_weight: -1)
      @@storages << FC::Storage.new(:name => 'read_storage-1',  :host => 'r1', :url => 'http://reader-1/sda/', url_weight: 0)
      @@storages.each(&:save)

      @@item_storage = FC::ItemStorage.new(:item_id => @@item.id, :storage_name => @@storages[0].name, :status => 'ready')
      @@item_storage.save
    end

    def shutdown
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM storages")
      FC::DB.query("DELETE FROM errors")
    end
  end

  setup do
    @@storages.each do |s|
      s.check_time = 0
      s.http_check_time = 0
      s.shared_group = nil
      s.save
    end
  end

  should 'read item from readable storage' do
    @@storages.each(&:update_check_time)
    assert_raise(RuntimeError) { @@item.url }

    @@storages.each do |s|
      s.shared_group = 'grp'
      s.save
    end

    available_storages = @@item.get_available_storages
    assert_equal 1, available_storages.size
    assert_equal 'read_storage-1', available_storages[0].name
    assert @@item.url

    # now with http_up
    stor = FC::Storage.new(:name => 'read_storage-2', :host => 'r2', :url => 'http://reader-2/sda/', url_weight: 1)
    stor.shared_group = 'grp'
    stor.save
    stor.update_check_time
    stor.update_http_check_time

    available_storages = @@item.get_available_storages
    assert_equal 1, available_storages.size
    assert_equal stor.name, available_storages[0].name
    assert_equal File.join(stor.url, @@item.name), @@item.url

    # with http_up and weight
    @@storages[1].update_http_check_time
    available_storages = @@item.get_available_storages
    assert_equal 2, available_storages.size
    assert_equal File.join(stor.url, @@item.name), @@item.url
    stor.delete
  end
end
