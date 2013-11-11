require 'helper'
require 'open3'
require 'timeout'

class DaemonTest < Test::Unit::TestCase
  class << self
    def startup
      @debug = false #show stdout and sterr of fc-daemon
      
      dir = File.expand_path(File.dirname(__FILE__))
      db_config_file = dir+'/db_test.yml'
      daemon_bin = File.expand_path(dir+'/../bin/fc-daemon')
      
      File.open(db_config_file, 'w') do |f|
        f.write(FC::DB.options.to_yaml)
      end
      
      @@errors_count = FC::Error.where.count
      
      FC::Var.set('daemon_cycle_time', 1)
      FC::Var.set('daemon_global_wait_time', 1)
      FC::Var.set('daemon_global_error_items_storages_ttl', 2)
      FC::Var.set('daemon_global_error_items_ttl', 2)
      @stotage_checks = 0
      Thread.new do
        Open3.popen2e("#{daemon_bin} -c #{db_config_file} -l debug -h host1") do |stdin, stdout, t|
          @@pid = t.pid
          while line = stdout.readline
            @stotage_checks += 1 if line =~ /Finish stotage check/i
            puts line if @debug
          end
        end
      end
      
      # tmp fake storages dirs
      `rm -rf /tmp/host*-sd*`
      `mkdir -p /tmp/host1-sda/ /tmp/host1-sdb/ /tmp/host1-sdc/`
      
      # test files to copy
      @@test_file_path = '/tmp/fc_test_file'
      `dd if=/dev/urandom of=#{@@test_file_path} bs=1M count=1 2>&1`
      @@test_dir_path = '/tmp/fc_test_dir'
      `mkdir -p #{@@test_dir_path}/aaa #{@@test_dir_path}/bbb`
      `cp #{@@test_file_path} #{@@test_dir_path}/aaa/test1`
      `cp #{@@test_file_path} #{@@test_dir_path}/bbb/test2`
      
      @@storages = []
      @@storages << FC::Storage.new(:name => 'host1-sda', :host => 'host1', :path => '/tmp/host1-sda/', :copy_storages => 'host1-sdb,host1-sdc', :size_limit => 1000000000)
      @@storages << FC::Storage.new(:name => 'host1-sdb', :host => 'host1', :path => '/tmp/host1-sdb/', :copy_storages => 'host1-sda,host1-sdc', :size_limit => 1000000000)
      @@storages << FC::Storage.new(:name => 'host1-sdc', :host => 'host1', :path => '/tmp/host1-sdc/', :copy_storages => 'host1-sda,host1-sdb', :size_limit => 1000000000)
      @@storages.each { |storage| storage.save}
      
      @@policy = FC::Policy.new(:create_storages => 'host1-sda,host1-sdb,host1-sdc', :copies => 2, :name => 'policy 1')
      @@policy.save
      
      # wait for running fc-daemon
      Timeout::timeout(5) do
        while @stotage_checks < @@storages.size
          sleep 0.1
        end
      end
    end
    
    def shutdown
      Process.kill("KILL", @@pid)
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM storages")
      `rm -rf /tmp/host*-sd*`
      `rm -rf #{@@test_file_path}`
      `rm -rf #{@@test_dir_path}`
    end
  end

  should "daemon_all" do
    @@storages.each {|storage| storage.reload}
    assert @@storages[0].up?, "Storage #{@@storages[0].name} down" 
    assert @@storages[1].up?, "Storage #{@@storages[1].name} down"
    
    FC::Storage.any_instance.stubs(:host).returns('host1')
    FC::Storage.stubs(:curr_host).returns('host1')
    assert_nothing_raised { @item1 = FC::Item.create_from_local(@@test_file_path, 'bla/bla/test1', @@policy, {:tag => 'test1'}) }
    assert_nothing_raised { @item2 = FC::Item.create_from_local(@@test_file_path, 'bla/bla/test2', @@policy, {:tag => 'test2'}) }
    assert_nothing_raised { @item3 = FC::Item.create_from_local(@@test_dir_path, 'bla/bla/test3', @@policy, {:tag => 'test3'}) }
    
    @@policy.copies = 3
    @@policy.save
    sleep 2
    
    # wait for copy
    [1, 2, 3].each do |i|
      ['b', 'c'].each do |j|
        assert_equal `du -sb /tmp/host1-sda/bla/bla/test$i 2>&1`.to_i, `du -sb /tmp/host$i-sd$j/bla/bla/test$i 2>&1`.to_i
      end
    end
    assert_equal @@errors_count, FC::Error.where.count, "new errors in errors table"
    
    @@policy.copies = 2
    @@policy.save
    item_storage = FC::ItemStorage.where('item_id = ? AND storage_name = ?', @item1.id, 'host1-sdc').first
    item_storage.status = 'delete'
    item_storage.save
    sleep 2
    assert_equal 0, `du -sb /tmp/host1-sdc/bla/bla/test1 2>&1`.to_i
    assert_equal @@errors_count, FC::Error.where.count, "new errors in errors table"
    
    @item1.mark_deleted
    FC::ItemStorage.where('item_id = ?', @item2.id).each do |item_storage|
      item_storage.status = 'error'
      item_storage.save
    end
    @item3.status = 'error'
    @item3.save
    
    sleep 6
    assert_raise(RuntimeError, "Item not deleted after mark_deleted") {@item1.reload}
    assert_equal 0, FC::ItemStorage.where('item_id = ?', @item2.id).count, "ItemStorages not deleted after status='error'"
    @item3.reload
    assert_equal 'delete', @item3.status, "ItemStorages not deleted after status='error'"    
    assert_equal @@errors_count, FC::Error.where.count, "new errors in errors table"
  end
end