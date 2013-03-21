require 'helper'

class BaseTest < Test::Unit::TestCase
  def setup
    @item = FC::Item.new(:name => 'test1', :tag => 'test tag', :dir => 0, :size => 100, :blabla => 'blabla')
  end
  should "correct init" do
    assert_raise(NoMethodError) { @item.blabla }
    assert @item, 'Item not created'
    assert_nil @item.id, 'Not nil id for new item'
  end
  
  should "correct add and save item" do
    @item.save
    assert id=@item.id, 'Nil id after save'
    # проверка на двойное сохранение
    @item.save
    assert_equal id, @item.id, 'Changed id after double save'
    @item.copies = 2
    @item.save
    assert_equal id, @item.id, 'Changed id after save with changes'
  end
  
  should "correct update and load item" do
    assert_raise(RuntimeError) { FC::Item.load(12454845) }
    @item.save
    @item.copies = 1
    @item.save
    @item.outer_id = 111
    @item.save
    loaded_item = FC::Item.load(@item.id)
    assert_kind_of FC::Item, loaded_item, 'Load not FC::Item'
    assert_equal @item.name, loaded_item.name, 'saved item name <> loaded item name'
    assert_equal @item.tag, loaded_item.tag, 'saved item tag <> loaded item tag'
    assert_equal @item.dir, loaded_item.dir, 'saved item dir <> loaded item dir'
    assert_equal @item.size, loaded_item.size, 'saved item size <> loaded item size'
    assert_equal @item.copies, loaded_item.copies, 'saved item copies <> loaded item copies'
    assert_equal @item.outer_id, loaded_item.outer_id, 'saved item outer_id <> loaded item outer_id'
    assert_equal 0, loaded_item.policy_id, 'Loaded item policy_id <> 0'
  end
  
  should "correct delete item" do
    assert_nothing_raised { @item.delete }
    assert_raise(RuntimeError) { FC::Item.load(@item.id) }
  end
end
