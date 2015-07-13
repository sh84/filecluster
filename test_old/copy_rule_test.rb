require 'helper'

class CopyRuleTest < Test::Unit::TestCase
  class << self
    def startup
      @@rules = []
      @@rules << FC::CopyRule.new(:copy_storages => 'rec2-sda,rec3-sda', :rule => 'size < 100')
      @@rules << FC::CopyRule.new(:copy_storages => 'rec1-sda,rec3-sda', :rule => 'name.match(/^test1/)')
      @@rules.each {|rule| rule.save}
      
      @@storages = []
      @@storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1', :size => 0, :size_limit => 100)
      @@storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2', :size => 0, :size_limit => 10)
      @@storages << FC::Storage.new(:name => 'rec3-sda', :host => 'rec3', :size => 0, :size_limit => 100)
      @@storages.each {|storage| storage.save}
    end
    def shutdown
      FC::DB.query("DELETE FROM copy_rules")
      FC::DB.query("DELETE FROM storages")
    end
  end
  
  should "rule check" do
    assert_equal true, @@rules[0].test
    assert_equal true, @@rules[0].check(1, 1, 1, '', '', false, nil)
    assert_equal false, @@rules[0].check(1, 100, 1, '', '', false, nil)
    assert_equal false, @@rules[1].test
    assert_equal false, @@rules[1].check(1, 1, 1, '', '', false, nil)
    assert_equal true, @@rules[1].check(1, 1, 1, 'test1/test', '', false, nil)
  end
  
  should "get_copy_storages" do
    FC::CopyRule.copy_storages_cache_time = 10
    assert_equal 'rec2-sda,rec3-sda', @@rules[0].get_copy_storages.map(&:name).join(',')
    @@rules[0].copy_storages = 'rec3-sda,rec2-sda'
    @@rules[0].save
    assert_equal 'rec2-sda,rec3-sda', @@rules[0].get_copy_storages.map(&:name).join(',')
    FC::CopyRule.copy_storages_cache_time = 0
    assert_equal 'rec3-sda,rec2-sda', @@rules[0].get_copy_storages.map(&:name).join(',')
  end
  
  should "all rules" do
    FC::CopyRule.rules_cache_time = 10
    assert_equal @@rules.map(&:id), FC::CopyRule.all.map(&:id)
    assert_equal 'rec1-sda,rec3-sda', FC::CopyRule.all[1].copy_storages
    @@rules[1].copy_storages = 'rec1-sda,rec2-sda'
    @@rules[1].save
    assert_equal 'rec1-sda,rec3-sda', FC::CopyRule.all[1].copy_storages
    FC::CopyRule.rules_cache_time = 0
    assert_equal 'rec1-sda,rec2-sda', FC::CopyRule.all[1].copy_storages
  end
  
  should "check_all" do
    assert_equal [], FC::CopyRule.check_all(1, 100, 1, '', '', false, nil)
    assert_same_elements [@@rules[0].id], FC::CopyRule.check_all(1, 1, 1, '', '', false, nil).map(&:id) 
    assert_same_elements [@@rules[0].id, @@rules[1].id], FC::CopyRule.check_all(1, 1, 1, 'test1/test', '', false, nil).map(&:id)
  end
  
  should "get_proper_storage_for_copy" do
    @@rules[0].copy_storages = 'rec2-sda,rec3-sda'
    @@rules[1].copy_storages = 'rec1-sda,rec3-sda'
    @@rules[0].save
    @@rules[1].save
    FC::CopyRule.rules_cache_time = 0
    FC::CopyRule.copy_storages_cache_time = 0
    
    @@storages.each {|storage| storage.check_time = 0; storage.save}
    assert_nil FC::CopyRule.get_proper_storage_for_copy(:size => 1), 'all storages down'

    @@storages[0].update_check_time
    assert_nil FC::CopyRule.get_proper_storage_for_copy(:size => 1), 'first storage up, but no rules with storage'
    assert_equal 'rec1-sda', FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test').name, 'first storage up'
    assert_nil FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :size => 200), 'first storage full'
    assert_nil FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :exclude => ['rec1-sda']), 'exclude'
    @@storages[1].update_check_time
    assert_equal 'rec2-sda', FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :size => 5).name, 'second storages up, small file'
    assert_equal 'rec1-sda', FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :size => 20).name, 'second storages up, big file'
    assert_nil FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :size => 1000), 'second storages up, very big file'
    @@storages[1].write_weight = 100
    @@storages[1].save
    @@storages[2].update_check_time
    assert_equal 'rec2-sda', FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :size => 1).name, 'all storages up, choose by weight'
    @@storages[1].write_weight = -1
    @@storages[1].save
    @@storages[2].write_weight = -1
    @@storages[2].save
    assert_equal 'rec1-sda', FC::CopyRule.get_proper_storage_for_copy(:name => 'test1/test', :size => 20).name, 'all storages up, 2 disabled by weight, work second rule'
  end
end
