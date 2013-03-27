# encoding: utf-8

module FC
  class Policy < DbBase
    set_table :policies, 'storages, copies'
    
    def get_storages
      FC::Storage.where("name IN (#{storages.split(',').map{|s| "'#{s}'"}.join(',')})")
    end
    
    # получить подходящий storage согласно policy для объекта размером size
    def get_proper_storage(size)
      get_storages.detect do |storage|
        storage.up? && storage.size + size < storage.size_limit
      end
    end
  end
end
