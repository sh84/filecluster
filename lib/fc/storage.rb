# encoding: utf-8
require 'shellwords'
require 'fileutils'

module FC
  class Storage < DbBase
    set_table :storages, 'name, host, path, url, size, size_limit, check_time, copy_storages, url_weight, write_weight'
    
    class << self
      attr_accessor :check_time_limit, :storages_cache_time, :get_copy_storages_mutex
    end
    @check_time_limit = 120 # ttl for up status check
    @storages_cache_time = 20 # ttl for storages cache
    @get_copy_storages_mutex = Mutex.new
    
    def self.curr_host
      @uname || @uname = `uname -n`.chomp
    end
    
    def self.select_proper_storage_for_create(storages, size, exclude = [])
      list = storages.select do |storage|
        !exclude.include?(storage.name) && storage.up? && storage.size + size < storage.size_limit && storage.write_weight.to_i >= 0
      end
      list = yield(list) if block_given?
      # sort by random(free_rate * write_weight)
      list.map{ |storage| 
        [storage, Kernel.rand(storage.free_rate * (storage.write_weight.to_i == 0 ? 0.01 : storage.write_weight.to_i) * 1000000000)] 
      }.sort{ |a, b|
        a[1] <=> b[1]
      }.map{|el| el[0]}.last
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
    
    def free
      size_limit - size
    end
    
    def size_rate
      size.to_f / size_limit
    end
    
    def free_rate
      rate = free.to_f / size_limit
      rate < 0 ? 0.0 : rate
    end
    
    def get_copy_storages
      self.class.get_copy_storages_mutex.synchronize do
        unless @copy_storages_cache && Time.new.to_i - @get_copy_storages_time.to_i < self.class.storages_cache_time
          @get_copy_storages_time = Time.new.to_i
          names = copy_storages.to_s.split(',').map{|s| "'#{s}'"}.join(',')
          @copy_storages_cache = names.empty? ? [] : FC::Storage.where("name IN (#{names}) ORDER BY FIELD(name, #{names})")
        end
      end
      @copy_storages_cache
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
    def copy_path(local_path, file_name, try_move = false, speed_limit = nil)
      dst_path = "#{self.path}#{file_name}"

      cmd = "rm -rf #{dst_path.shellescape}; mkdir -p #{File.dirname(dst_path).shellescape}"
      cmd = self.class.curr_host == host ? cmd : "ssh -q -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"#{cmd}\""
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      
      op = try_move && self.class.curr_host == host && File.stat(local_path).dev == File.stat(File.dirname(dst_path)).dev ? 'mv' : 'cp -r'
      speed_limit = (speed_limit * 1000).to_i if speed_limit.to_f > 0
      cmd = self.class.curr_host == host ?
        "#{op} #{local_path.shellescape} #{dst_path.shellescape}" :
        "scp -r -q -oBatchMode=yes -oStrictHostKeyChecking=no #{speed_limit.to_i > 0 ? '-l '+speed_limit.to_s : ''} #{local_path.shellescape} #{self.host}:\"#{dst_path.shellescape}\""
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
    
    # copy object to local_path
    def copy_to_local(file_name, local_path, speed_limit = nil)
      src_path = "#{self.path}#{file_name}"
      
      r = `rm -rf #{local_path.shellescape}; mkdir -p #{File.dirname(local_path).shellescape} 2>&1`
      raise r if $?.exitstatus != 0
      
      speed_limit = (speed_limit * 1000).to_i if speed_limit.to_f > 0
      cmd = self.class.curr_host == host ? 
        "cp -r #{src_path.shellescape} #{local_path.shellescape}" : 
        "scp -r -q -oBatchMode=yes -oStrictHostKeyChecking=no #{speed_limit.to_i > 0 ? '-l '+speed_limit.to_s : ''} #{self.host}:\"#{src_path.shellescape}\" #{local_path.shellescape}"
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
    end
    
    # delete object from storage
    def delete_file(file_name)
      dst_path = "#{self.path}#{file_name}"
      if self.class.curr_host == host
        begin
          File.delete(dst_path)
        rescue Errno::EISDIR
          FileUtils.rm_r(dst_path)
        end
      else
        cmd = "ssh -q -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"rm -rf #{dst_path.shellescape}\""
        r = `#{cmd} 2>&1`
        raise r if $?.exitstatus != 0
        
        cmd = "ssh -q -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"ls -la #{dst_path.shellescape}\""
        r = `#{cmd} 2>/dev/null`
        raise "Path #{dst_path} not deleted" unless r.empty?
      end
    end
    
    # return object size on storage
    def file_size(file_name, ignore_errors = false)
      dst_path = "#{self.path}#{file_name}"
      
      cmd = self.class.curr_host == host ? 
        "du -sb #{dst_path.shellescape}" : 
        "ssh -q -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"du -sb #{dst_path.shellescape}\""
      r = ignore_errors ? `#{cmd} 2>/dev/null` : `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      r.to_i
    end
    
    # return object md5_sum on storage
    def md5_sum(file_name)
      dst_path = "#{self.path}#{file_name}"
      cmd = self.class.curr_host == host ?
          "find #{dst_path.shellescape} -type f -exec md5sum {} \\; | awk '{print $1}' | sort | md5sum" :
          "ssh -q -oBatchMode=yes -oStrictHostKeyChecking=no #{self.host} \"find #{dst_path.shellescape} -type f -exec md5sum {} \\; | awk '{print \\$1}' | sort | md5sum\""
      r = `#{cmd} 2>&1`
      raise r if $?.exitstatus != 0
      r.to_s[0..31]
    end
    
    # get available storage for copy by size
    def get_proper_storage_for_copy(size, exclude = [])
      FC::Storage.select_proper_storage_for_create(get_copy_storages, size, exclude)
    end
  end
end
