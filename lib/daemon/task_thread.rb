class TaskThread < BaseThread
  def go(storage_name)
    while task = $tasks[storage_name].shift do
      if task[:action] == :delete
        make_delete(task[:item_storage])
      elsif task[:action] == :copy
        make_copy(task[:item_storage])
      else
        error "Unknown task action: #{task[:action]}"
      end
    end
  end
  
  def make_delete(item_storage)
    storage = $storages.detect{|s| s.name == item_storage.storage_name}
    item = FC::Item.find(item_storage.item_id)
    storage.delete_file(item_storage.name)
    item_storage.delete
  rescue Exception => e
    error "Delete item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => item_storage.item_id, :item_storage_id => item_storage.id
  end
  
  def make_copy(item_storage)
    storage = $storages.detect{|s| s.name == item_storage.storage_name}
    item = FC::Item.find(item_storage.item_id)
    src_item_storage = FC::ItemStorage.where("item_id = ? AND status = 'ready'", item.id).sample
    src_storage = $storages.detect{|s| s.name == src_item_storage.storage_name}
    item.copy_item_storage(src_storage, storage, item_storage)
  rescue Exception => e
    error "Copy item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => item_storage.item_id, :item_storage_id => item_storage.id
  end
end