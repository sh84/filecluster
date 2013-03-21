require 'helper'

class DbTest < Test::Unit::TestCase
  def setup
    @item = FC::Item.new(:id => 12, :name => 'rrr')
  end
  context 'ggg' do
    should "test" do
      assert @item
    end
  end
end
