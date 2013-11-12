class UpdateTasksThread < BaseThread
  def go
    $log.debug('Update tasks')
    check_tasks(:delete)
    check_tasks(:copy)
  end
  
  def check_tasks(type)
    count = 0
    tasks = (type == :copy ? $tasks_copy : $tasks_delete) 
    $storages.each do |storage|
      tasks[storage.name] = [] unless tasks[storage.name]
      cond = "storage_name = '#{storage.name}' AND status='#{type.to_s}'"
      ids = tasks[storage.name].map(&:id) + $curr_tasks.map(&:id)
      limit = FC::Var.get("daemon_tasks_#{type}_group_limit", 1000).to_i
      cond << "AND id not in (#{ids.join(',')})" if ids.length > 0
      cond << " LIMIT #{limit}"
      FC::ItemStorage.where(cond).each do |item_storage|
        tasks[storage.name] << item_storage 
        $log.debug("task add: type=#{type}, item_storage=#{item_storage.id}")
        count +=1 
      end
    end
    $log.debug("Add #{count} #{type} tasks")
  end
end