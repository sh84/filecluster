# encoding: utf-8

module FC
  class Storage < DbBase
    set_table :storages, 'name, host, path, url, size, size_limit, check_time'
    
    class << self
      attr_accessor :check_time_limit
    end
    @check_time_limit = 120
    
    def self.curr_host
      @uname || @uname = `uname -n`
    end
    
    def update_check_time
      self.check_time = Time.new.to_i
      self.save
    end
    
    def up?
      Time.new.to_i - self.check_time <= self.class.check_time_limit
    end
    
    # копирование локального пути на машину storage
    def copy_path(local_path, name)
      r = `scp -r TODO koo:/jhome/vhosts/filecluster/ 2>&1`
      raice r if $?.exitstatus != 0
    end
  end
end
