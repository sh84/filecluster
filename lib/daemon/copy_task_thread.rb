class CopyTaskThread < BaseThread
  def go(storage_name)
    return unless $tasks_copy[storage_name]
    Thread.current[:tasks_processed] = 0 unless Thread.current[:tasks_processed]
    while task = $tasks_copy[storage_name].shift do
      $curr_tasks << task
      $log.debug("CopyTaskThread(#{storage_name}): run task for item_storage ##{task.id}, copy_count=#{$copy_count}/#{$copy_cont_avg}, copy_speed=#{$copy_speed}")
      make_copy(task)
      $curr_tasks.delete(task)
      $log.debug("CopyTaskThread(#{storage_name}): finish task for item_storage ##{task.id}")
      Thread.current[:tasks_processed] += 1
      exit if $exit_signal
    end
  end
  
  def make_copy(task)
    sleep 0.1 while $copy_count > FC::Var.get('daemon_copy_tasks_per_host_limit', 10).to_i
    limit = FC::Var.get_current_speed_limit
    speed_limit = nil
    if limit
      if $copy_count == 0
        $copy_speed = 0
        speed_limit = limit * 0.75
      elsif $copy_count <= $copy_cont_avg && (speed_limit = limit / $copy_cont_avg) < limit * 1.1 - $copy_speed
      else
        while (speed_limit = (limit - $copy_speed) * 0.75) < limit*0.1 do
          sleep 0.1
        end
      end
    end
    $copy_count += 1
    $copy_speed += speed_limit if speed_limit
    calc_avg_count()
    
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
    available_src_storages = FC::ItemStorage.where("item_id = ? AND status = 'ready'", item.id)
                                            .map do |item_storage|
      $all_storages.detect { |a_storage| a_storage.name == item_storage.storage_name && a_storage.up? }
    end.compact

    # pref for current host
    src_storage = available_src_storages.detect { |src| src.host == storage.host }
    # pref for same dc
    src_storage = available_src_storages.detect { |src| src.dc == storage.dc } unless src_storage
    # random from available storages
    src_storage = available_src_storages.sample unless src_storage

    unless src_storage
      $log.warn("Item ##{item.id} #{item.name} has no ready item_storage or storage")
      return nil 
    end
    $log.debug("Copy from #{src_storage.name} to #{storage.name} #{storage.path}#{item.name}")
    item.copy_item_storage(src_storage, storage, task, false, speed_limit)
  rescue Exception => e
    error "Copy item_storage error: #{e.message}; #{e.backtrace.join(', ')}", :item_id => task.item_id, :item_storage_id => task.id
    $curr_tasks.delete(task)
  ensure 
    $copy_count -= 1 if $copy_count > 0
    $copy_speed -= speed_limit if speed_limit
  end

  def calc_avg_count
    $copy_cont_avg = ($copy_count + $copy_cont_avg) / 2.0
  end
end
