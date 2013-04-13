# encoding: utf-8

module FC
  class Policy < DbBase
    set_table :policies, 'storages, copies'
    
    class << self
      attr_accessor :storages_cache_time
    end
    @storages_cache_time = 20 # ttl for storages cache
    
    def get_storages
      return @storages_cache if @storages_cache && Time.new.to_i - @get_storages_time.to_i < self.class.storages_cache_time
      @get_storages_time = Time.new.to_i
      @storages_cache = FC::Storage.where("name IN (#{storages.split(',').map{|s| "'#{s}'"}.join(',')})")
    end
    
    # get available storage for object by size
    def get_proper_storage(size, exclude = [])
      get_storages.detect do |storage|
        !exclude.include?(storage.name) && storage.up? && storage.size + size < storage.size_limit
      end
    end
  end
end
