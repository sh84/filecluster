class UpdateTasksThread < BaseThread
  def go
    $log.debug('Update tasks')
    check_tasks(:delete)
    check_tasks(:copy)
  end
  
  def check_tasks(type)
    storages_names = $storages.map{|storage| "'#{storage.name}'"}.join(',')
    return if storages_names.empty?
    cond = "storage_name in (#{storages_names}) AND status='#{type.to_s}'"
    ids = $tasks.map{|storage_name, storage_tasks| storage_tasks.select{|task| task[:action] == type}}.
      flatten.map{|task| task[:item_storage].id}
    ids += $curr_tasks.select{|task| task[:action] == type}.map{|task| task[:item_storage].id}
    
    limit = FC::Var.get('daemon_global_tasks_group_limit', 1000).to_i
    cond << "AND id not in (#{ids.join(',')})" if (ids.length > 0)
    cond << " LIMIT #{limit}"
    FC::ItemStorage.where(cond).each do |item_storage|
      unless ids.include?(item_storage.id)
        $tasks[item_storage.storage_name] = [] unless $tasks[item_storage.storage_name]
        $tasks[item_storage.storage_name] << {:action => type, :item_storage => item_storage} 
        $log.debug("task add: type=#{type}, item_storage=#{item_storage.id}")
      end
    end
  end
end