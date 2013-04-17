class TaskThread < BaseThread
  def go(storage_name)
    while task = $tasks[storage_name].shift do
      $curr_task[storage_name] = task
      $log.debug("TaskThread(#{storage_name}): run task type=#{task[:action]}, item_storage=#{task[:item_storage].id}")
      if task[:action] == :delete
        make_delete(task[:item_storage])
      elsif task[:action] == :copy
        make_copy(task[:item_storage])
      else
        error "Unknown task action: #{task[:action]}"
      end
      $curr_task[storage_name] = nil
      $log.debug("TaskThread(#{storage_name}): Finish task type=#{task[:action]}, item_storage=#{task[:item_storage].id}")
    end
  end
  
  def make_delete(item_storage)
    storage = $storages.detect{|s| s.name == item_storage.storage_name}
    item = FC::Item.find(item_storage.item_id)
    storage.delete_file(item.name)
    item_storage.delete
  rescue Exception => e
    error "Delete item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => item_storage.item_id, :item_storage_id => item_storage.id
  end
  
  def make_copy(item_storage)
    # TODO: не лазить в базу за item, item_storages - перенести на стадию подготовки task-а
    storage = $storages.detect{|s| s.name == item_storage.storage_name}
    item = FC::Item.find(item_storage.item_id)
    src_item_storage = FC::ItemStorage.where("item_id = ? AND status = 'ready'", item.id).sample
    src_storage = $all_storages.detect{|s| s.name == src_item_storage.storage_name}
    $log.debug("Copy from #{src_storage.name} to #{storage.name} #{storage.path}#{item.name}")
    item.copy_item_storage(src_storage, storage, item_storage)
  rescue Exception => e
    error "Copy item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => item_storage.item_id, :item_storage_id => item_storage.id
  end
end