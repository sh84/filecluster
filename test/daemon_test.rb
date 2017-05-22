require 'helper'
require 'open3'
require 'timeout'

class DaemonTest < Test::Unit::TestCase
  class << self
    def startup
      @@debug = false # show stdout and sterr of fc-daemon
      
      dir = File.expand_path(File.dirname(__FILE__))
      db_config_file = "#{dir}/db_test.yml"
      daemon_bin = File.expand_path("#{dir}/../bin/fc-daemon")
      
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
        Open3.popen2e("#{daemon_bin} -c #{db_config_file} -l debug -h localhost") do |stdin, stdout, t|
          @@pid = t.pid
          while line = stdout.readline
            @stotage_checks += 1 if line =~ /Finish stotage check/i
            puts line if @@debug
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
      @@storages << FC::Storage.new(
        :name => 'host1-sda',
        :host => 'localhost',
        :path => '/tmp/host1-sda/',
        :copy_storages => 'host1-sdb,host1-sdc', 
        :size_limit => 1_000_000_000
      )
      @@storages << FC::Storage.new(
        :name => 'host1-sdb',
        :host => 'localhost',
        :path => '/tmp/host1-sdb/',
        :copy_storages => 'host1-sda,host1-sdc', 
        :size_limit => 1_000_000_000
      )
      @@storages << FC::Storage.new(
        :name => 'host1-sdc',
        :host => 'localhost',
        :path => '/tmp/host1-sdc/',
        :copy_storages => 'host1-sda,host1-sdb',
        :size_limit => 1_000_000_000
      )
      @@storages.each(&:save)
      
      @@policy = FC::Policy.new(
        :create_storages => 'host1-sda,host1-sdb,host1-sdc', 
        :copies => 2, 
        :name => 'policy 1',
        :delete_deferred_time => 7
      )
      @@policy.save
      
      @@rule = FC::CopyRule.new(:copy_storages => 'host1-sdc', :rule => 'name == "bla/bla/test3"')
      @@rule.save
      
      # wait for running fc-daemon
      Timeout.timeout(5) do
        sleep 0.1 while @stotage_checks < @@storages.size
      end
    end
    
    def shutdown
      Process.kill('KILL', @@pid)
      FC::DB.query('DELETE FROM items_storages')
      FC::DB.query('DELETE FROM items')
      FC::DB.query('DELETE FROM policies')
      FC::DB.query('DELETE FROM storages')
      `rm -rf /tmp/host*-sd*`
      `rm -rf #{@@test_file_path}`
      `rm -rf #{@@test_dir_path}`
    end
  end

  should 'daemon_all' do
    puts 'Start' if @@debug
    @@storages.each(&:reload)
    assert @@storages[0].up?, "Storage #{@@storages[0].name} down" 
    assert @@storages[1].up?, "Storage #{@@storages[1].name} down"
    assert @@storages[2].up?, "Storage #{@@storages[2].name} down"
    
    assert_nothing_raised { @item1 = make_file_item('bla/bla/test1', 'test1') }
    assert_nothing_raised { @item2 = make_file_item('bla/bla/test2', 'test2') }
    assert_nothing_raised { @item3 = make_dir_item('bla/bla/test3', 'test3') }
    assert_nothing_raised { @item4 = make_file_item('bla/bla/test4', 'test4') }
    
    @@policy.copies = 3
    @@policy.save

    # wait for copy
    sleep 2
    puts 'Check copy' if @@debug
    [1, 2, 3, 4].each do |i|
      %w(b c).each do |j|
        src_size = `du -sb /tmp/host$i-sda/bla/bla/test$i 2>&1`.to_i
        dst_size = `du -sb /tmp/host$i-sd$j/bla/bla/test$i 2>&1`.to_i
        assert_equal src_size, dst_size
      end
    end
    assert_equal @@errors_count, FC::Error.where.count, 'new errors in errors table'
    
    @@policy.copies = 2
    @@policy.save
    item_storage = FC::ItemStorage.where('item_id = ? AND storage_name = ?', @item1.id, 'host1-sdc').first
    item_storage.status = 'delete'
    item_storage.save
    
    sleep 2
    puts 'Check delete' if @@debug
    assert_equal 0, `du -sb /tmp/host1-sdc/bla/bla/test1 2>&1`.to_i
    assert_equal @@errors_count, FC::Error.where.count, 'new errors in errors table'
    
    @item1.immediate_delete
    @item4.mark_deleted
    @item2.get_item_storages.each do |ist|
      ist.status = 'error'
      ist.save
    end
    @item3.status = 'error'
    @item3.save
    
    sleep 6
    puts 'Check immediate_delete' if @@debug
    assert_raise(RuntimeError, 'Item not deleted after mark_deleted') { @item1.reload }
    assert_equal 0, @item2.get_item_storages.count, "ItemStorages not deleted after status='error'"
    @item3.reload
    assert_equal 'delete', @item3.status, "ItemStorages not deleted after status='error'"
    assert_equal @@errors_count, FC::Error.where.count, 'new errors in errors table'
    assert_equal 'deferred_delete', @item4.status, 'Item not deferred_delete after mark_deleted'
    assert_same_elements %w(ready ready ready), @item4.get_item_storages.map(&:status)

    sleep 6
    puts 'Check mark_deleted' if @@debug
    assert_raise(RuntimeError, 'Item not deleted after mark_deleted') { @item4.reload }
  end

  private

  def make_file_item(name, tag)
    FC::Item.create_from_local(@@test_file_path, name, @@policy, :tag => tag)
  end

  def make_dir_item(name, tag)
    FC::Item.create_from_local(@@test_dir_path, name, @@policy, :tag => tag)
  end
end
