require 'helper'

Test::Unit.at_start do
  storages = []
  storages << FC::Storage.new(:name => 'rec1-sda', :host => 'rec1')
  storages << FC::Storage.new(:name => 'rec1-sdb', :host => 'rec1')
  storages << FC::Storage.new(:name => 'rec1-sdc', :host => 'rec1')
  storages << FC::Storage.new(:name => 'rec1-sdd', :host => 'rec1')
  storages << FC::Storage.new(:name => 'rec2-sda', :host => 'rec2')
  storages << FC::Storage.new(:name => 'rec2-sdb', :host => 'rec2')
  storages << FC::Storage.new(:name => 'rec2-sdc', :host => 'rec2')
  storages << FC::Storage.new(:name => 'rec2-sdd', :host => 'rec2')
  $storages_ids = storages.map{|storage| storage.save; storage.id }
  
  p = FC::Policy.new(:storages => 'rec1-sda,rec2-sda', :copies => 2)
  p.save
  $policy_id = p.id
end

Test::Unit.at_exit do
  FC::DB.connect.query("DELETE FROM storages")
  FC::DB.connect.query("DELETE FROM policies")
end

class DbTest < Test::Unit::TestCase
  def setup
    @storages = $storages_ids.map{|id| FC::Storage.find(id)}
    @policy = FC::Policy.find($policy_id)
  end
  context 'ggg' do
    should "test" do
      puts @storages
      puts @policy
    end
  end
end
