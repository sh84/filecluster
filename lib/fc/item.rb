# encoding: utf-8

module FC
  class Item < DbBase
    set_table :items, 'name, tag, outer_id, policy_id, dir, size, status, time, copies'
    
    # Create item by local path.
    # Additional options: 
    #   :replace=true - replace item if it exists
    # If item_name is part of local_path it processed as inplace - local_path is valid path to the item for policy
    def self.create_from_local(local_path, item_name, policy, options={})
      raise 'Path not exists' unless File.exists?(local_path)
      raise 'Policy is not FC::Policy' unless policy.instance_of?(FC::Policy)
      item_params = options.merge({
        :name => item_name.to_s.gsub('//', '/').sub(/\/$/, '').sub(/^\//, '').strip,
        :policy_id => policy.id,
        :dir => File.directory?(local_path),
        :size => `du -sb #{local_path}`.to_i
      })
      item_params.delete(:replace)
      item_params.delete(:inplace)
      raise 'Name is empty' if item_params[:name].empty?
      raise 'Zero size path' if item_params[:size] == 0
      
      if local_path.include?(item_name)
        storage = policy.get_create_storages.detect do |s| 
          s.host == FC::Storage.curr_host && local_path.index(s.path) == 0 && local_path.sub(s.path, '') == item_params[:name]
        end
        FC::Error.raise "local_path #{local_path} is not valid path for policy ##{policy.id}" unless storage
      end
      
      # new item?
      item = FC::Item.where('name=? AND policy_id=?', item_params[:name], policy.id).first
      if item
        if options[:replace] || storage
          # replace all fields
          item_params.each{|key, val| item.send("#{key}=", val)}
        else
          FC::Error.raise 'Item already exists', :item_id => item.id
        end
      else
        item = FC::Item.new(item_params)
      end
      item.save
      
      if storage
        item_storage = item.make_item_storage(storage, 'ready')
        item.reload
      else 
        storage = policy.get_proper_storage_for_create(item.size)
        FC::Error.raise 'No available storage', :item_id => item.id unless storage
        
        # mark delete item_storages on replace
        FC::DB.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{item.id} AND storage_name <> '#{storage.name}'") if options[:replace]          
        
        item_storage = item.make_item_storage(storage)
        item.copy_item_storage(local_path, storage, item_storage)
      end
      
      return item
    end
    
    def make_item_storage(storage, status = 'new')
      # new storage_item?
      item_storage = FC::ItemStorage.where('item_id=? AND storage_name=?', id, storage.name).first
      item_storage.delete if item_storage
      
      item_storage = FC::ItemStorage.new({:item_id => id, :storage_name => storage.name, :status => status})
      item_storage.save
      item_storage
    end
    
    def copy_item_storage(src, storage, item_storage)
      begin
        if src.instance_of?(FC::Storage)
          src.copy_to_local(name, "#{storage.path}#{name}")
        else
          storage.copy_path(src, name)
        end
        size_on_storage = storage.file_size(name)
      rescue Exception => e
        item_storage.status = 'error'
        item_storage.save
        FC::Error.raise "Copy error: #{e.message}", :item_id => id, :item_storage_id => item_storage.id
      else
        begin
          item_storage.reload
        rescue Exception => e
          FC::Error.raise "After copy error: #{e.message}", :item_id => id, :item_storage_id => item_storage.id
        else
          if size_on_storage != size
            item_storage.status = 'error'
            item_storage.save
            FC::Error.raise "Check size after copy error", :item_id => id, :item_storage_id => item_storage.id
          else
            item_storage.status = 'ready'
            item_storage.save
            reload
          end
        end
      end
    end
    
    # mark items_storages for delete
    def mark_deleted
      FC::DB.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{id}")
      self.status = 'delete'
      save
    end
    
    def dir?
      dir.to_i == 1
    end
    
    def get_item_storages
      FC::ItemStorage.where("item_id = #{id}")
    end
    
    def get_available_storages
      r = FC::DB.query("SELECT st.* FROM #{FC::Storage.table_name} as st, #{FC::ItemStorage.table_name} as ist WHERE 
        ist.item_id = #{id} AND ist.status='ready' AND ist.storage_name = st.name")
      r.map{|data| FC::Storage.create_from_fiels(data)}.select {|storage| storage.up? }
    end
  end
end
