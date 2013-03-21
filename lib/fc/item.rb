# encoding: utf-8

module FC
  class Item < DbBase
    set_table :items, 'id, name, tag, outer_id, policy_id, dir, size, status, time, copies'
    
    def initialize(params = {})
      super(params)
    end
    
    # создает item по локальному файлу
    def self.create_from_local(local_path, path, policy, options={})
      FC::Item.new
    end
  end
end
