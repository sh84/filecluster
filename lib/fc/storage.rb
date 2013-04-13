# encoding: utf-8

module FC
  class Storage < DbBase
    set_table :storages, 'name, host, path, url, size, size_limit, check_time'
    
    class << self
      attr_accessor :check_time_limit
    end
    @check_time_limit = 120 # ttl for up status check
    
    def self.curr_host
      @uname || @uname = `uname -n`.chomp
    end
    
    def initialize(params = {})
      path = (params['path'] || params[:path])
      if path && !path.to_s.empty?
        raise "Storage path must be like '/bla/bla../'" unless path.match(/^\/.*\/$/)
      end
      super params
    end
    
    def update_check_time
      self.check_time = Time.new.to_i
      save
    end
    
    def check_time_delay
      Time.new.to_i - check_time.to_i
    end
    
    def up?
      Time.new.to_i - check_time.to_i < self.class.check_time_limit
    end
    
    # copy local_path to storage
    def copy_path(local_path, file_name)
      cmd = self.class.curr_host == host ? 
        "cp -r #{local_path} #{self.path}#{file_name}" : 
        "scp -rB #{local_path} #{self.host}:#{self.path}#{file_name}"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
    
    # copy object to local_path
    def copy_to_local(file_name, local_path)
      cmd = self.class.curr_host == host ? 
        "cp -r #{self.path}#{file_name} #{local_path}" : 
        "scp -rB #{self.host}:#{self.path}#{file_name} #{local_path}"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
    
    # delete object from storage
    def delete_file(file_name)
      cmd = self.class.curr_host == host ? 
        "rm -rf #{self.path}#{file_name}" : 
        "ssh -oBatchMode=yes #{self.host} 'rm -rf #{self.path}#{file_name}'"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      
      cmd = self.class.curr_host == host ? 
        "ls -la #{self.path}#{file_name}" : 
        "ssh -oBatchMode=yes #{self.host} 'ls -la #{self.path}#{file_name}'"
      r = `#{cmd} 2>/dev/null`
      raise "Path #{self.path}#{file_name} not deleted" unless r.empty?
    end
    
    # return object size on storage
    def file_size(file_name)
      cmd = self.class.curr_host == host ? 
        "du -sb #{self.path}#{file_name}" : 
        "ssh -oBatchMode=yes #{self.host} 'du -sb #{self.path}#{file_name}'"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      r.to_i
    end
  end
end
