# encoding: utf-8

module FC
  class Policy < DbBase
    set_table :policies, 'storages, copies'
    
    def get_storages
      FC::Storage.where("name IN (#{storages.split(',').map{|s| "'#{s}'"}.join(',')})")
    end
    
    # get available storage for object by size
    def get_proper_storage(size, exclude = [])
      get_storages.detect do |storage|
        !exclude.include?(storage.name) && storage.up? && storage.size + size < storage.size_limit
      end
    end
  end
end
