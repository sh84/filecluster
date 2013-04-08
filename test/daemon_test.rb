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
      
      @stotage_checks = 0
      Thread.new do
        Open3.popen2e("#{daemon_bin} -c #{db_config_file} -l debug -t 1 -g 1 -h host1") do |stdin, stdout, t|
          @@pid = t.pid
          while line = stdout.readline
            @stotage_checks += 1 if line =~ /Finish stotage check/i
            puts line if @debug
          end
        end
      end
      
      # tmp fake storages dirs
      `rm -rf /tmp/host*-sd*`
      `mkdir -p /tmp/host1-sda/ /tmp/host1-sdb/`
      
      # test file to copy
      @@test_file_path = '/tmp/fc_test_file'
      `dd if=/dev/urandom of=#{@@test_file_path} bs=100K count=1 2>&1`
      
      @@storages = []
      @@storages << FC::Storage.new(:name => 'host1-sda', :host => 'host1', :path => '/tmp/host1-sda/', :size_limit => 1000000)
      @@storages << FC::Storage.new(:name => 'host1-sdb', :host => 'host1', :path => '/tmp/host1-sdb/', :size_limit => 1000000)
      @@storages.each { |storage| storage.save}
      
      @@policy = FC::Policy.new(:storages => 'host1-sda,host1-sdb', :copies => 2)
      @@policy.save
      
      # wait for running fc-daemon
      Timeout::timeout(5) do
        while @stotage_checks < 2
          sleep 0.1
        end
      end
    end
    
    def shutdown
      Process.kill("KILL", @@pid)
      FC::DB.connect.query("DELETE FROM items_storages")
      FC::DB.connect.query("DELETE FROM items")
      FC::DB.connect.query("DELETE FROM policies")
      FC::DB.connect.query("DELETE FROM storages")
      `rm -rf /tmp/host1-sda /tmp/host2-sda`
    end
  end
  
  should "daemon_all" do
    @@storages.each { |storage| storage.reload}
    assert @@storages[0].up?, "Storage #{@@storages[0].name} down" 
    assert @@storages[1].up?, "Storage #{@@storages[1].name} down"
    
    FC::Storage.any_instance.stubs(:host).returns('host1')
    FC::Storage.stubs(:curr_host).returns('host1')
    assert_nothing_raised { @item = FC::Item.create_from_local(@@test_file_path, 'test1', @@policy, {:tag => 'test1'}) }
    # wait for copy
    sleep 1
    assert_equal `du -b /tmp/host1-sda/test1 2>&1`.to_i, `du -b /tmp/host1-sdb/test1 2>&1`.to_i
  end
end