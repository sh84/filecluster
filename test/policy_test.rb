require 'helper'

class PolicyTest < Test::Unit::TestCase
  class << self
    def startup
      @@storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1', :size => 0, :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2', :size => 0, :size_limit => 100)
      @@storages.each {|storage| storage.save}
      
      @@policy = FC::Policy.new(:storages => 'rec1-sda,rec2-sda', :copies => 1)
      @@policy.save
    end
    def shutdown
      FC::DB.connect.query("DELETE FROM policies")
      FC::DB.connect.query("DELETE FROM storages")
    end
  end 

  should "get_storages" do
    assert_same_elements @@storages.map(&:id), @@policy.get_storages.map(&:id)
  end
  
  should "get_proper_storage" do
    assert_nil @@policy.get_proper_storage(1), 'all storages down'
    @@storages[0].update_check_time
    assert_equal @@storages[0].id, @@policy.get_proper_storage(1).id, 'first storages up'
    assert_nil @@policy.get_proper_storage(20), 'first storage full'
    @@storages[1].update_check_time
    assert_equal @@storages[1].id, @@policy.get_proper_storage(20).id, 'second storages up'
    assert_nil @@policy.get_proper_storage(1000), 'all storages full'
  end
  
end
