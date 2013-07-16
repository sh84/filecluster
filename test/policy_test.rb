require 'helper'

class PolicyTest < Test::Unit::TestCase
  class << self
    def startup
      @@storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1', :size => 0, :copy_id => 1, :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2', :size => 0, :copy_id => 2 , :size_limit => 100)
      @@storages << FC::Storage.new(:name => 'rec2-sdb', :host => 'rec2', :size => 0, :copy_id => 4 , :size_limit => 100)
      @@storages.each {|storage| storage.save}
      @@storage3 = FC::Storage.new(:name => 'rec3-sda', :host => 'rec3', :size => 8, :copy_id => 3 , :size_limit => 10)
      @@storage3.save
            
      @@policy = FC::Policy.new(:create_storages => 'rec1-sda,rec2-sda,rec2-sdb', :copy_storages => 'rec1-sda,rec2-sda', :copies => 1, :name => 'policy 1')
      @@policy.save
    end
    def shutdown
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
    end
  end 

  should "get_create_storages" do
    FC::Policy.storages_cache_time = 10
    assert_same_elements @@storages.map(&:id), @@policy.get_create_storages.map(&:id)
    @@policy.create_storages = 'rec1-sda,rec2-sda'
    @@policy.save
    assert_equal @@storages.size, @@policy.get_create_storages.size
    FC::Policy.storages_cache_time = 0
    assert_equal 2, @@policy.get_create_storages.size
  end
  
  should "get_copy_storages" do
    @@policy.copy_storages = 'rec1-sda,rec2-sda,rec2-sdb'
    @@policy.save
    FC::Policy.storages_cache_time = 10
    assert_same_elements @@storages.map(&:id), @@policy.get_copy_storages.map(&:id)
    @@policy.copy_storages = 'rec1-sda,rec2-sda'
    @@policy.save
    assert_equal @@storages.size, @@policy.get_copy_storages.size
    FC::Policy.storages_cache_time = 0
    assert_equal 2, @@policy.get_copy_storages.size
  end
  
  should "get_proper_storage_for_create" do
    @@storages.each {|storage| storage.check_time = 0; storage.save}
    @@storage3.check_time = 0
    @@storage3.save
    FC::Policy.storages_cache_time = 0
    assert_nil @@policy.get_proper_storage_for_create(1), 'all storages down'
    @@storages[0].update_check_time
    assert_equal @@storages[0].id, @@policy.get_proper_storage_for_create(5).id, 'first storages up'
    assert_nil @@policy.get_proper_storage_for_create(20), 'first storage full'
    @@storages[1].update_check_time
    assert_equal @@storages[1].id, @@policy.get_proper_storage_for_create(20).id, 'second storages up'
    assert_nil @@policy.get_proper_storage_for_create(1000), 'all storages full'
  end
  
  should "get_proper_storage_for_copy" do
    @@storages.each {|storage| storage.check_time = 0; storage.save}
    FC::Policy.storages_cache_time = 0
    assert_nil @@policy.get_proper_storage_for_copy(1), 'all storages down'
    @@storages[0].update_check_time
    @@storage3.update_check_time
    assert_equal @@storages[0].id, @@policy.get_proper_storage_for_copy(5).id, 'first storages up'
    assert_nil @@policy.get_proper_storage_for_copy(20), 'first storage full'
    @@storages[1].update_check_time
    assert_equal @@storages[1].id, @@policy.get_proper_storage_for_copy(20).id, 'second storages up'
    assert_nil @@policy.get_proper_storage_for_copy(1000), 'all storages full'
    
    @@policy.copy_storages = 'rec3-sda,rec1-sda,rec2-sda'
    @@policy.save
    assert_equal 'rec3-sda', @@policy.get_proper_storage_for_copy(1).name, 'first storage in copy_storages'
    assert_equal 'rec2-sda', @@policy.get_proper_storage_for_copy(1, 2).name, 'storage by copy_id'
    @@policy.copy_storages = 'rec1-sda,rec3-sda'
    @@policy.save
    assert_equal 'rec3-sda', @@policy.get_proper_storage_for_copy(1, 2).name, 'storage by copy_id'
    @@policy.copy_storages = 'rec3-sda,rec1-sda,rec2-sda,rec2-sdb'
    @@policy.save
    assert_equal 'rec2-sda', @@policy.get_proper_storage_for_copy(1, 4).name, 'storage by copy_id'
    @@policy.copy_storages = 'rec2-sda,rec3-sda,rec1-sda,rec2-sdb'
    @@policy.save
    @@storages[2].update_check_time
    assert_equal 'rec2-sdb', @@policy.get_proper_storage_for_copy(1, 4).name, 'storage by copy_id'
    
    @@policy.copy_storages = 'rec3-sda,rec1-sda,rec2-sda'
    @@policy.save
    @@storages[0].check_time = 0
    @@storages[0].save
    assert_equal 'rec3-sda', @@policy.get_proper_storage_for_copy(1, 1).name, 'storage by copy_id'
  end
  
  should "filter_by_host" do
    FC::Storage.stubs(:curr_host).returns('rec2')
    FC::Policy.new(:create_storages => 'rec3-sda,rec2-sda', :copy_storages => 'rec1-sda,rec2-sda', :copies => 1, :name => 'policy 2').save
    FC::Policy.new(:create_storages => 'rec1-sda,rec3-sda', :copy_storages => 'rec1-sda,rec2-sda', :copies => 1, :name => 'policy 3').save
    assert_same_elements ['policy 1', 'policy 2'], FC::Policy.filter_by_host.map{|p| p.name}
  end
end
