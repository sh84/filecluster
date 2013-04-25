# encoding: utf-8

module FC
  class Policy < DbBase
    set_table :policies, 'name, create_storages, copy_storages, copies'
    
    class << self
      attr_accessor :storages_cache_time
    end
    @storages_cache_time = 20 # ttl for storages cache
    
    def self.filter_by_host(host = nil)
      host = FC::Storage.curr_host unless host
      self.where.select do |policy|
        policy.get_create_storages.detect{|storage| storage.host == host}
      end
    end
    
    def get_create_storages
      return @create_storages_cache if @create_storages_cache && Time.new.to_i - @get_create_storages_time.to_i < self.class.storages_cache_time
      @get_create_storages_time = Time.new.to_i
      names = create_storages.split(',').map{|s| "'#{s}'"}.join(',')
      @create_storages_cache = FC::Storage.where("name IN (#{names}) ORDER BY FIELD(name, #{names})")
    end
    
    def get_copy_storages
      return @copy_storages_cache if @copy_storages_cache && Time.new.to_i - @get_copy_storages_time.to_i < self.class.storages_cache_time
      @get_copy_storages_time = Time.new.to_i
      names = copy_storages.split(',').map{|s| "'#{s}'"}.join(',')
      @copy_storages_cache = FC::Storage.where("name IN (#{names}) ORDER BY FIELD(name, #{names})")
    end
    
    # get available storage for create by size
    def get_proper_storage_for_create(size, exclude = [])
      get_create_storages.detect do |storage|
        !exclude.include?(storage.name) && storage.up? && storage.size + size < storage.size_limit
      end
    end
    
    # get available storage for copy by copy_id and size
    def get_proper_storage_for_copy(size, copy_id = nil, exclude = [])
      storages = get_copy_storages
      start_storage_index = nil
      storages.each_with_index do |s, i|
        start_storage_index = i if copy_id.to_i == s.copy_id.to_i && !exclude.include?(s.name)
      end
      storages = storages[start_storage_index..-1]+storages[0..start_storage_index-1] if storages.size > 0 && start_storage_index
      storages = storages.select do |storage|
        !exclude.include?(storage.name) && storage.up? && storage.size + size < storage.size_limit
      end
      storage = storages.detect{|s| copy_id.to_i == s.copy_id.to_i}
      storage = storages.detect{|s| copy_id.to_i < s.copy_id.to_i} unless storage
      storage = storages.first unless storage
      storage
    end
  end
end
