# encoding: utf-8

module FC
  class Policy < DbBase
    set_table :policies, 'name, create_storages, copies'
    
    class << self
      attr_accessor :storages_cache_time, :get_create_storages_mutex
    end
    @storages_cache_time = 20 # ttl for storages cache
    @get_create_storages_mutex = Mutex.new
    
    def self.filter_by_host(host = nil)
      host = FC::Storage.curr_host unless host
      self.where.select do |policy|
        policy.get_create_storages.detect{|storage| storage.host == host}
      end
    end
    
    def get_create_storages
      self.class.get_create_storages_mutex.synchronize do
        unless @create_storages_cache && Time.new.to_i - @get_create_storages_time.to_i < self.class.storages_cache_time
          @get_create_storages_time = Time.new.to_i
          names = create_storages.to_s.split(',').map{|s| "'#{s}'"}.join(',')
          @create_storages_cache = names.empty? ? [] : FC::Storage.where("name IN (#{names}) ORDER BY FIELD(name, #{names})")
        end
      end
      @create_storages_cache
    end
    
    # get available storage for create by size and local item path
    def get_proper_storage_for_create(size, local_path = nil)
      FC::Storage.select_proper_storage_for_create(get_create_storages, size) do |storages|
        local_storages = storages.select{|storage| FC::Storage.curr_host == storage.host}
        # find same storage device as local_path device
        if local_path && !local_storages.empty?
          dev = File.stat(local_path).dev
          dev_storage = local_storages.select{|storage| dev == File.stat(storage.path).dev}.first
          local_storages = [dev_storage] if dev_storage
        end
        # if no local storages - use all storages
        local_storages = storages if local_storages.empty?
        local_storages
      end
    end
  end
end
