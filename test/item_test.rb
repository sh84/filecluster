require 'helper'

class ItemTest < Test::Unit::TestCase
  def setup
    @item = FC::Item.new()
  end
  context 'ggg' do
    should "test" do
    assert @item
    end
  end
end
