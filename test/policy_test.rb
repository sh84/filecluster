require 'helper'

class PolicyTest < Test::Unit::TestCase
  class << self
    def startup
      @@storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1', :path => '/tmp/host1-sda/', :size => 0, :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec1-sdb', :host => 'rec1', :path => '/tmp/host1-sdb/', :size => 0, :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2', :path => '/tmp/host2-sda/', :size => 30, :size_limit => 100)
      @@storages << FC::Storage.new(:name => 'rec2-sdb', :host => 'rec2', :path => '/tmp/host2-sdb/', :size => 20, :size_limit => 100)
      @@storages << FC::Storage.new(:name => 'rec2-sdc', :host => 'rec2', :path => '/tmp/host2-sdc/', :size => 10, :size_limit => 100)
      @@storages << FC::Storage.new(:name => 'rec3-sda', :host => 'rec3', :path => '/tmp/host3-sda/', :size => 99, :size_limit => 1000)
      @@storages << FC::Storage.new(:name => 'rec3-sdb', :host => 'rec3', :path => '/tmp/host3-sdb/', :size => 199, :size_limit => 1000)
      @@storages.each {|storage| storage.save}
      
      @@policy = FC::Policy.new(:create_storages => 'rec1-sda,rec2-sda,rec2-sdb,rec2-sdc,rec3-sda,rec3-sdb', :copies => 1, :name => 'policy 1')
      @@policy.save
    end
    def shutdown
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
    end
  end 

  should "get_create_storages" do
    FC::Policy.storages_cache_time = 10
    assert_equal 6, @@policy.get_create_storages.size
    @@policy.create_storages = 'rec1-sda,rec2-sda'
    @@policy.save
    assert_equal 6, @@policy.get_create_storages.size
    FC::Policy.storages_cache_time = 0
    assert_equal 2, @@policy.get_create_storages.size
    @@policy.create_storages = 'rec1-sda,rec2-sda,rec2-sdb,rec2-sdc,rec3-sda,rec3-sdb'
    @@policy.save
  end
  
  should "filter_by_host" do
    FC::Storage.stubs(:curr_host).returns('rec2')
    FC::Policy.new(:create_storages => 'rec3-sda,rec2-sda', :copy_storages => 'rec1-sda,rec2-sda', :copies => 1, :name => 'policy 2').save
    FC::Policy.new(:create_storages => 'rec1-sda,rec3-sda', :copy_storages => 'rec1-sda,rec2-sda', :copies => 1, :name => 'policy 3').save
    assert_same_elements ['policy 1', 'policy 2'], FC::Policy.filter_by_host.map{|p| p.name}
  end
  
  should "get_proper_storage_for_create" do
    FC::Policy.storages_cache_time = 0
    @@storages.each {|storage| storage.check_time = 0; storage.save}
    assert_nil @@policy.get_proper_storage_for_create(1), 'all storages down'
    @@storages[0].update_check_time
    assert_kind_of FC::Storage, @@policy.get_proper_storage_for_create(5), 'first storages up'
    assert_equal 'rec1-sda', @@policy.get_proper_storage_for_create(5).name, 'first storages up'
    assert_nil @@policy.get_proper_storage_for_create(20), 'first storage full'
    @@storages[2].update_check_time
    assert_equal 'rec2-sda', @@policy.get_proper_storage_for_create(20).name, 'second storages up'
    assert_nil @@policy.get_proper_storage_for_create(1000), 'all storages full'
  end
  
  should "get_proper_storage_for_create for local path" do
    FC::Policy.storages_cache_time = 0
    @@storages.each {|storage| storage.update_check_time}
    FC::Storage.stubs(:curr_host).returns('rec2')
    File.stubs(:stat).with('test-rec2-sdb').returns(OpenStruct.new :dev => 10)
    File.stubs(:stat).with('/tmp/host2-sdb/').returns(OpenStruct.new :dev => 10)
    File.stubs(:stat).with{|s| s != 'test-rec2-sdb' && s != '/tmp/host2-sdb/'}.returns(OpenStruct.new :dev => 0)
    assert_equal 'rec2-sdb', @@policy.get_proper_storage_for_create(9, 'test-rec2-sdb').name, 'current host, dev match'
    @@storages[3].check_time = 0;
    @@storages[3].save
    assert_equal 'rec2-sdc', @@policy.get_proper_storage_for_create(9, 'test-rec2-sdb').name, 'current host, most free storage'
    FC::Storage.stubs(:curr_host).returns('rec3')
    @@storages[5].check_time = 0;
    @@storages[5].save
    assert_equal 'rec3-sdb', @@policy.get_proper_storage_for_create(9, 'test-rec2-sdb').name, 'current host, single storage'
    FC::Storage.stubs(:curr_host).returns('rec5')
    assert_equal 'rec1-sda', @@policy.get_proper_storage_for_create(9, 'test-rec2-sdb').name, 'not current host, most free storage'
    assert_equal 'rec2-sdc', @@policy.get_proper_storage_for_create(10, 'test-rec2-sdb').name, 'not current host, big file, most free storage with free space'
    File.unstub(:stat)
  end
end