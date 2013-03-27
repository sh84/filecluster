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
    
    def initialize(params = {})
      path = (params['path'] || params[:path])
      if path && !path.to_s.empty?
        raise "Storage path must be like '/bla/bla../'" unless path.match(/^\/.*\/$/)
      end
      super params
    end
    
    def update_check_time
      check_time = Time.new.to_i
      save
    end
    
    def up?
      Time.new.to_i - check_time <= self.class.check_time_limit
    end
    
    # копирование локального пути на машину storage
    def copy_path(local_path, file_name)
      cmd = self.class.curr_host == host ? 
        "cp -r #{local_path} #{self.path}#{file_name}" : 
        "scp -rB #{local_path} #{self.host}:#{self.path}#{file_name}"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
  end
end
