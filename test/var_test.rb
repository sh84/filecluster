require 'helper'

class VarTest < Test::Unit::TestCase
  should "set and get" do
    assert_nothing_raised {FC::Var.set('test1', 111)}
    assert_nothing_raised {FC::Var.set(:test2, '222')}
    assert_equal '111', FC::Var.get(:test1)
    assert_equal '222', FC::Var.get('test2')
  end
  should "change" do
    assert_nothing_raised {FC::Var.set('test3', '333')}
    assert_equal '333', FC::Var.get('test3')
    FC::Var.set('test3', '3332')
    assert_equal '3332', FC::Var.get('test3')
  end
  should "get all" do
    assert_nothing_raised {FC::Var.set('test4', '444')}
    assert_nothing_raised {FC::Var.set('test5', '555')}
    assert_nothing_raised {FC::Var.set('test6', '666')}
    vars = FC::Var.get_all
    assert_equal '444', vars['test4']
    assert_equal '555', vars[:test5]
    assert_equal '666', vars[:test6]
  end
  should "change and get all" do
    assert_nothing_raised {FC::Var.set('test7', '777')}
    vars = FC::Var.get_all
    assert_equal '777', vars['test7']
    FC::Var.set('test7', '7772')
    vars = FC::Var.get_all
    assert_equal '7772', vars['test7']
  end
end