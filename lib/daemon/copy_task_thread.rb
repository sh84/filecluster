class CopyTaskThread < BaseThread
  def go(storage_name)
    return unless $tasks_copy[storage_name]
    Thread.current[:tasks_processed] = 0 unless Thread.current[:tasks_processed]
    while task = $tasks_copy[storage_name].shift do
      $curr_tasks << task
      $log.debug("CopyTaskThread(#{storage_name}): run task for item_storage ##{task.id}, copy_count=#{$copy_count}")
      make_copy(task)
      $curr_tasks.delete(task)
      $log.debug("CopyTaskThread(#{storage_name}): finish task for item_storage ##{task.id}")
      Thread.current[:tasks_processed] += 1
      exit if $exit_signal
    end
  end
  
  def make_copy(task)
    sleep 0.1 while $copy_count > FC::Var.get('daemon_copy_tasks_per_host_limit', 10).to_i
    $copy_count += 1
    storage = $storages.detect{|s| s.name == task.storage_name}
    begin
      item = FC::Item.find(task.item_id)
    rescue Exception => e
      if e.message.match('Record not found')
        $log.warn("Item ##{task.item_id} not found before copy")
        return nil
      else 
        raise e
      end
    end
    return nil unless item && item.status == 'ready'
    src_item_storage = FC::ItemStorage.where("item_id = ? AND status = 'ready'", item.id).sample
    unless src_item_storage
      $log.warn("Item ##{item.id} #{item.name} has no ready item_storage")
      return nil 
    end
    src_storage = $all_storages.detect{|s| s.name == src_item_storage.storage_name}
    $log.debug("Copy from #{src_storage.name} to #{storage.name} #{storage.path}#{item.name}")
    item.copy_item_storage(src_storage, storage, task)
  rescue Exception => e
    error "Copy item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => task.item_id, :item_storage_id => task.id
    $curr_tasks.delete(task)
  ensure 
    $copy_count -= 1 if $copy_count > 0
  end
end