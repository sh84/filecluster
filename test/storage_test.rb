require 'helper'

class StorageTest < Test::Unit::TestCase
  should "curr_host" do
    assert ! FC::Storage.curr_host.to_s.empty?
  end
  
  should "initialize" do
    assert_raise(RuntimeError) { FC::Storage.new :path => 'test' }
    assert_raise(RuntimeError) { FC::Storage.new :path => '/test' }
    assert_raise(RuntimeError) { FC::Storage.new :path => 'test/' }
    assert_nothing_raised { FC::Storage.new :path => '/test/' }
  end
  
  should "update_check_time and up?" do
    storage = FC::Storage.new(:name => 'rec1-sda', :host => 'rec1')
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
  
end
