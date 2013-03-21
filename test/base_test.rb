require 'helper'

class BaseTest < Test::Unit::TestCase
  def setup
    @item = FC::Item.new(:name => 'test1', :tag => 'test tag', :dir => 0, :dir => '', :size => 100)
  end
  should "correct init" do
    assert_raise(NoMethodError) { FC::Item.new(:blabla => 'blabla') }
    assert @item
    assert_nil @item.id
  end
  should "correct save new item" do
    @item.save
    puts @item.inspect
    assert @item.id
    puts @item.inspect
  end
end
