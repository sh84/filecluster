# encoding: utf-8
require 'shellwords'

module FC
  class Storage < DbBase
    set_table :storages, 'name, host, path, url, size, size_limit, check_time, copy_id'
    
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
        path += '/' unless path[-1] == '/'
        raise "Storage path must be like '/bla/bla../'" unless path.match(/^\/.*\/$/)
        params['path'] = params[:path] = path
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
      check_time_delay < self.class.check_time_limit
    end
    
    # copy local_path to storage
    def copy_path(local_path, file_name)
      dst_path = "#{self.path}#{file_name}"
      
      cmd = "rm -rf #{dst_path.shellescape}; mkdir -p #{File.dirname(dst_path).shellescape}"
      cmd = self.class.curr_host == host ? cmd : "ssh -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"#{cmd}\""
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      
      cmd = self.class.curr_host == host ? 
        "cp -r #{local_path.shellescape} #{dst_path.shellescape}" : 
        "scp -rB #{local_path.shellescape} #{self.host}:\"#{dst_path.shellescape}\""
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
    
    # copy object to local_path
    def copy_to_local(file_name, local_path)
      src_path = "#{self.path}#{file_name}"
      
      r = `rm -rf #{local_path.shellescape}; mkdir -p #{File.dirname(local_path).shellescape} 2>&1`
      raise r if $?.exitstatus != 0
      
      cmd = self.class.curr_host == host ? 
        "cp -r #{src_path.shellescape} #{local_path.shellescape}" : 
        "scp -rB #{self.host}:\"#{src_path.shellescape}\" #{local_path.shellescape}"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
    
    # delete object from storage
    def delete_file(file_name)
      dst_path = "#{self.path}#{file_name}"
      cmd = self.class.curr_host == host ? 
        "rm -rf #{dst_path.shellescape}" : 
        "ssh -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"rm -rf #{dst_path.shellescape}\""
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      
      cmd = self.class.curr_host == host ? 
        "ls -la #{dst_path.shellescape}" : 
        "ssh -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"ls -la #{dst_path.shellescape}\""
      r = `#{cmd} 2>/dev/null`
      raise "Path #{dst_path} not deleted" unless r.empty?
    end
    
    # return object size on storage
    def file_size(file_name, ignore_errors = false)
      dst_path = "#{self.path}#{file_name}"
      
      cmd = self.class.curr_host == host ? 
        "du -sb #{dst_path.shellescape}" : 
        "ssh -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"du -sb #{dst_path.shellescape}\""
      r = ignore_errors ? `#{cmd} 2>/dev/null` : `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      r.to_i
    end
  end
end
