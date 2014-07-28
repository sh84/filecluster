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
    
    # get available storages for create by size
    def get_proper_storages_for_create(size, exclude = [])
      get_create_storages.select do |storage|
        !exclude.include?(storage.name) && storage.up? && storage.size + size < storage.size_limit
      end
    end
    
    # get available storage for create by size
    def get_proper_storage_for_create(size, exclude = [])
      get_proper_storages_for_create(size, exclude).first
    end
  end
end
