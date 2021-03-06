require 'helper'

class BaseTest < Test::Unit::TestCase
  class << self
    def shutdown
      FC::DB.query("DELETE FROM items")
    end
  end
  
  def setup
    @@policy_id ||= 1
    @item = FC::Item.new(:name => 'test1', :tag => 'test tag', :dir => 0, :size => 100, :blabla => 'blabla', :policy_id => @@policy_id)
    @@policy_id += 1
  end
  
  should "correct init" do
    assert_raise(NoMethodError, 'Set not table field') { @item.blabla }
    assert @item, 'Item not created'
    assert_nil @item.id, 'Not nil id for new item'
  end
  
  should "correct add and save item" do
    @item.save
    assert id=@item.id, 'Nil id after save'
    # double save check
    @item.save
    assert_equal id, @item.id, 'Changed id after double save'
    @item.copies = 2
    @item.save
    assert_equal id, @item.id, 'Changed id after save with changes'
  end
  
  should "correct where" do
    @item.save
    ids = [@item.id]
    item2 = FC::Item.new(:name => 'test2', :tag => 'test tag', :dir => 0, :size => 100, :blabla => 'blabla', :policy_id => 100)
    item2.save
    ids << item2.id
    items = FC::Item.where("id IN (#{ids.join(',')})")
    assert_same_elements items.map(&:id), ids, "Items by where load <> items by find"
  end
  
  should "correct reload item" do
    @item.save
    @item.name = 'new test'
    @item.tag = 'new test tag'
    @item.dir = '1'
    @item.size = '777'
    @item.reload
    assert_same_elements ['test1', 'test tag', 0, 100], [@item.name, @item.tag, @item.dir, @item.size], 'Fields not restoted after reload'
  end
  
  should "correct update and load item" do
    assert_raise(RuntimeError) { FC::Item.find(12454845) }
    @item.save
    @item.copies = 1
    @item.save
    @item.outer_id = 111
    @item.save
    loaded_item = FC::Item.find(@item.id)
    assert_kind_of FC::Item, loaded_item, 'Load not FC::Item'
    assert_equal @item.name, loaded_item.name, 'Saved item name <> loaded item name'
    assert_equal @item.tag, loaded_item.tag, 'Saved item tag <> loaded item tag'
    assert_equal @item.dir, loaded_item.dir, 'Saved item dir <> loaded item dir'
    assert_equal @item.size, loaded_item.size, 'Saved item size <> loaded item size'
    assert_equal @item.copies, loaded_item.copies, 'Saved item copies <> loaded item copies'
    assert_equal @item.outer_id, loaded_item.outer_id, 'Saved item outer_id <> loaded item outer_id'
  end
  
  should "correct delete item" do
    assert_nothing_raised { @item.delete }
    assert_raise(RuntimeError, 'Item not deleted') { FC::Item.find(@item.id) }
  end
end
