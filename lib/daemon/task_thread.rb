class TaskThread < BaseThread
  def go(storage_name)
    return unless $tasks[storage_name]
    while task = $tasks[storage_name].shift do
      $curr_tasks << task
      $log.debug("TaskThread(#{storage_name}): run task type=#{task[:action]}, item_storage=#{task[:item_storage].id}")
      if task[:action] == :delete
        make_delete(task)
      elsif task[:action] == :copy
        make_copy(task)
      else
        error "Unknown task action: #{task[:action]}"
      end
      $curr_tasks.delete(task)
      $log.debug("TaskThread(#{storage_name}): Finish task type=#{task[:action]}, item_storage=#{task[:item_storage].id}")
    end
  end
  
  def make_delete(task)
    item_storage = task[:item_storage]
    # TODO: не лазить в базу за item
    storage = $storages.detect{|s| s.name == item_storage.storage_name}
    item = FC::Item.find(item_storage.item_id)
    storage.delete_file(item.name)
    item_storage.delete
  rescue Exception => e
    error "Delete item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => item_storage.item_id, :item_storage_id => item_storage.id
    $curr_tasks.delete(task)
  end
  
  def make_copy(task)
    item_storage = task[:item_storage]
    # TODO: не лазить в базу за item, item_storages - перенести на стадию подготовки task-а
    storage = $storages.detect{|s| s.name == item_storage.storage_name}
    item = FC::Item.find(item_storage.item_id)
    src_item_storage = FC::ItemStorage.where("item_id = ? AND status = 'ready'", item.id).sample
    unless src_item_storage
      $log.info("Item ##{item.id} #{item.name} has no ready item_storage")
      return nil 
    end
    src_storage = $all_storages.detect{|s| s.name == src_item_storage.storage_name}
    $log.debug("Copy from #{src_storage.name} to #{storage.name} #{storage.path}#{item.name}")
    item.copy_item_storage(src_storage, storage, item_storage)
  rescue Exception => e
    error "Copy item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => item_storage.item_id, :item_storage_id => item_storage.id
    $curr_tasks.delete(task)
  end
end