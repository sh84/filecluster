require 'helper'

class BaseTest < FC::TestCase  
  def test_correct_init
    item = FC::Item.new
    assert_raises(NoMethodError, 'Set not table field') { @item.blabla }
    assert_nil item.id, 'Not nil id for new item'
  end
  
  def test_save_load_and_delete_item
    item = FC::Item.new(:name => 'test1', :policy_id => 1, :copies => 1, :blabla => 'blabla', :tag => 'test tag')
    item.save
    assert id=item.id, 'Nil id after save'
    # double save check
    item.save
    assert_equal id, item.id, 'Changed id after double save'
    item.copies = 2
    item.save
    assert_equal id, item.id, 'Changed id after save with changes'
    
    item.name = 'new test'
    item.tag = 'new test tag'
    item.reload
    assert_equal_contents ['test1', 'test tag'], [item.name, item.tag], 'Fields not restoted after reload'
    
    item_copy = FC::Item.find(id)
    assert_kind_of FC::Item, item_copy
    assert_equal item.name, item_copy.name
    assert_equal item.policy_id, item_copy.policy_id
    assert_equal item.tag, item_copy.tag
    assert_equal item.copies, item_copy.copies
    
    # no change - no save
    item_copy.tag = 'new tag'
    item_copy.save
    item.save
    item_copy.reload
    assert_equal 'new tag', item_copy.tag
    # force save
    item.save!
    item_copy.reload
    assert_equal 'test tag', item_copy.tag
    
    item.delete
    assert_raises(RuntimeError) { FC::Item.find(id) }
  end
  
  def test_correct_where_and_count
    item = FC::Item.create(:name => 'test1', :policy_id => 1)
    item2 = FC::Item.create(:name => 'test2', :policy_id => 1)
    items = FC::Item.where("id = ? OR id = ?", item.id, item2.id)
    assert_equal_contents items.map(&:id), [item.id, item2.id], "Items by where load <> items by find"
    assert_equal 2, FC::Item.count("id = ? OR id = ?", item.id, item2.id)
  ensure 
    item.delete
    item2.delete
  end
end
