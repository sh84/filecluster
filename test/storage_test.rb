require 'helper'

class StorageTest < Test::Unit::TestCase
  class << self
    def startup
      @@storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1', :size => 0, :copy_storages => 'rec2-sda,rec3-sda', :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2', :size => 0, :copy_storages => 'rec1-sda,rec3-sda', :size_limit => 100)
      @@storages << FC::Storage.new(:name => 'rec3-sda', :host => 'rec3', :size => 8, :copy_storages => 'rec1-sda,rec2-sda', :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec2-sdb', :host => 'rec2', :size => 0, :size_limit => 100)
      @@storages.each {|storage| storage.save}
      
      @@policy = FC::Policy.new(:create_storages => 'rec1-sda,rec2-sda,rec2-sdb', :copies => 1, :name => 'policy 1')
      @@policy.save
    end
    def shutdown
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
    end
  end 
  
  should "curr_host" do
    assert ! FC::Storage.curr_host.to_s.empty?
  end
  
  should "initialize" do
    assert_raise(RuntimeError) { FC::Storage.new :path => 'test' }
    assert_raise(RuntimeError) { FC::Storage.new :path => 'test/' }
    assert_nothing_raised { FC::Storage.new :path => '/test/' }
  end
  
  should "update_check_time and up?" do
    storage = FC::Storage.new(:name => 'rec1-test', :host => 'rec1')
    storage.save
    assert_equal false, storage.up?
    storage.update_check_time
    assert_equal true, storage.up?
    storage.reload
    assert_equal true, storage.up?
    storage.check_time = Time.now.to_i - FC::Storage.check_time_limit - 1
    storage.save
    assert_equal false, storage.up?
    storage.delete
  end
  
  should "get_copy_storages" do
    @@storages[2].copy_storages = 'rec1-sda,rec2-sda,rec2-sdb'
    @@storages[2].save
    FC::Storage.storages_cache_time = 10
    assert_equal 'rec1-sda,rec2-sda,rec2-sdb', @@storages[2].get_copy_storages.map(&:name).join(',')
    @@storages[2].copy_storages = 'rec1-sda,rec2-sda'
    @@storages[2].save
    assert_equal 'rec1-sda,rec2-sda,rec2-sdb', @@storages[2].get_copy_storages.map(&:name).join(',')
    FC::Storage.storages_cache_time = 0
    assert_equal 'rec1-sda,rec2-sda', @@storages[2].get_copy_storages.map(&:name).join(',')
  end
  
  should "get_proper_storage_for_copy" do
    @@storages.each {|storage| storage.check_time = 0; storage.save}
    @@storages[3].update_check_time
    assert_nil @@storages[3].get_proper_storage_for_copy(1), 'empty copy_storages'
    assert_nil @@storages[2].get_proper_storage_for_copy(1), 'all storages down'

    @@storages[0].update_check_time
    assert_equal 'rec1-sda', @@storages[2].get_proper_storage_for_copy(5).name, 'first storages up'
    assert_nil @@storages[2].get_proper_storage_for_copy(20), 'first storage full'
    @@storages[1].update_check_time
    @@storages[0].write_weight = 100
    @@storages[0].save
    assert_equal 'rec1-sda', @@storages[2].get_proper_storage_for_copy(5).name, 'second storages up, small file'
    assert_equal 'rec2-sda', @@storages[2].get_proper_storage_for_copy(20).name, 'second storages up, big file'
    assert_nil @@storages[2].get_proper_storage_for_copy(1000), 'second storages up, huge file'
  end
  
  should "free and rate" do
    storage = @@storages[0]
    storage.size = 1
    assert_equal 9, storage.free, 'first storage free must be size_limit - size'
    assert_equal 9.to_f/10, storage.free_rate, 'first storage free_rate must be free/size_limit' 
    assert_equal 1.to_f/10, storage.size_rate, 'first storage free must be size/size_limit'
  end
end
