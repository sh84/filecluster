# encoding: utf-8

module FC
  class Item < DbBase
    set_table :items, 'name, tag, outer_id, policy_id, dir, size, status, time, copies'
    
    # создает item по локальному файлу
    def self.create_from_local(local_path, name, policy, options={})
      raise 'Path not exists' unless File.exists?(local_path)
      raise 'Policy is not FC::Policy' unless policy.instance_of?(FC::Policy)
      item_params = options.merge({
        :name => name.to_s.gsub('//', '/').sub(/\/$/, '').sub(/^\//, '').strip,
        :policy_id => policy.id,
        :dir => File.directory?(local_path),
        :size => `du -sb #{local_path}`.to_i
      })
      raise 'Name is empty' if item_params[:name].empty?
      raise 'Zero size path' if item_params[:size] == 0
      # TODO проверка на уникальность имени
      # TODO учет некорректных попыток копирования
      
      item = FC::Item.new(item_params)
      item.save
      
      storage = policy.get_proper_storage(item_params[:size])
      item_storage = FC::ItemStorage.new({:item_id => item.id, :storage_name => storage.name, :status => 'copy'})
      storage.copy_path(local_path, name)
      
    end
    
    # помечает items_storages на удаление
    def mark_deleted
      FC::DB.connect.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{self.id}")
      self.status = 'delete'
      self.save
    end
    
    def dir?
      self.dir.to_i == 1
    end
    
    def get_item_storages
      FC:ItemStorage.where("item_id = #{self.id}")
    end
  end
end
