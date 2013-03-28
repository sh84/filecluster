require 'helper'

class ErrorTest < Test::Unit::TestCase
  def setup
    FC::Storage.stubs(:curr_host).returns('localhost')
  end
  
  should "get_storages" do
    assert_raise(RuntimeError) { FC::Error.raise 'error message', :item_id => 111 }
    assert error = FC::Error.where('1 ORDER BY id desc LIMIT 1').first
    assert_equal 'error message', error.message
    assert_equal 'localhost', error.host
    assert_equal 111, error.item_id
  end
end
