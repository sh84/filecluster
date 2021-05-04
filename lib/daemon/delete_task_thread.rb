class DeleteTaskThread < BaseThread
  def go(storage_name)
    return unless $tasks_delete[storage_name]
    Thread.current[:tasks_processed] = 0 unless Thread.current[:tasks_processed]
    while task = $tasks_delete[storage_name].shift do
      $curr_tasks << task
      $log.debug("DeleteTaskThread(#{storage_name}): run task for item_storage ##{task.id}")
      make_delete(task)
      $curr_tasks.delete(task)
      $log.debug("DeleteTaskThread(#{storage_name}): finish task for item_storage ##{task.id}")
      Thread.current[:tasks_processed] += 1
      exit if $exit_signal
    end
  end
  
  def make_delete(task)
    storage = $storages.detect{|s| s.name == task.storage_name}
    begin
      item = FC::Item.find(task.item_id)
    rescue Exception => e
      if e.message.match('Record not found')
        $log.warn("Item ##{task.item_id} not found before delete")
        task.delete
        return nil
      else 
        raise e
      end
    end
    $log.debug("Delete #{storage.path}#{item.name}")
    storage.delete_file(item.name)
    task.delete
  rescue Exception => e
    error "Delete item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => task.item_id, :item_storage_id => task.id
    $curr_tasks.delete(task)
  end
end