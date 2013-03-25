# encoding: utf-8

module FC
  class Item < DbBase
    set_table :items, 'name, tag, outer_id, policy_id, dir, size, status, time, copies'
    
    # создает item по локальному файлу
    def self.create_from_local(local_path, path, policy, options={})
      FC::Item.new
    end
    
    # помечает items_storages на удаление
    def mark_deleted
      FC::DB.connect.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{self.id}")
      self.status = 'delete'
      self.save
    end
  end
end
