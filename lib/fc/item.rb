# encoding: utf-8

module FC
  class Item < DbBase
    set_table :items, 'name, tag, outer_id, policy_id, dir, size, status, time, copies'
    
    # создает item по локальному файлу
    def self.create_from_local(local_path, item_name, policy, options={})
      raise 'Path not exists' unless File.exists?(local_path)
      raise 'Policy is not FC::Policy' unless policy.instance_of?(FC::Policy)
      item_params = options.merge({
        :name => item_name.to_s.gsub('//', '/').sub(/\/$/, '').sub(/^\//, '').strip,
        :policy_id => policy.id,
        :dir => File.directory?(local_path),
        :size => `du -sb #{local_path}`.to_i
      })
      raise 'Name is empty' if item_params[:name].empty?
      raise 'Zero size path' if item_params[:size] == 0
      # TODO проверка на уникальность имени
      
      item = FC::Item.new(item_params)
      item.save
      
      storage = policy.get_proper_storage(item_params[:size])
      # TODO а может уже существует
      item_storage = FC::ItemStorage.new({:item_id => item.id, :storage_name => storage.name, :status => 'copy'})
      
      begin  
        storage.copy_path(local_path, item_params[:name])
      rescue Exception => e
        item_storage.status = 'error'
        item_storage.save
        # TODO учет некорректных попыток копирования
        raise e.message
      else
        # TODO проверить размер
        item_storage.status = 'ready'
        item_storage.save
        return item
      end
    end
    
    # помечает items_storages на удаление
    def mark_deleted
      FC::DB.connect.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{id}")
      status = 'delete'
      save
    end
    
    def dir?
      dir.to_i == 1
    end
    
    def get_item_storages
      FC::ItemStorage.where("item_id = #{id}")
    end
  end
end
