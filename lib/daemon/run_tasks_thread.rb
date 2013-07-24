class RunTasksThread < BaseThread
  def go
    $log.debug("Run tasks (copy_count: #{$copy_count})")
    $storages.each do |storage|
      $tasks_threads[storage.name] = [] unless $tasks_threads[storage.name]
      $tasks_threads[storage.name].delete_if {|thread| !thread.alive?}
      tasks_count = $tasks[storage.name] ? $tasks[storage.name].size : 0
      threads_count = $tasks_threads[storage.name].count
      
      # <max_threads> tasks per thread, maximum <tasks_per_thread> threads
      max_threads = FC::Var.get('daemon_global_tasks_threads_limit', 10).to_i
      tasks_per_thread = FC::Var.get('daemon_global_tasks_per_thread', 10).to_i
      
      run_threads_count = (tasks_count/tasks_per_thread.to_f).ceil
      run_threads_count = max_threads if run_threads_count > max_threads
      run_threads_count = run_threads_count - threads_count
      
      $log.debug("tasks_count: #{tasks_count}, threads_count: #{threads_count}, run_threads_count: #{run_threads_count}")
      run_threads_count.times do
        $log.debug("spawn TaskThread for #{storage.name}") 
        $tasks_threads[storage.name] << TaskThread.new(storage.name)
      end
    end
  end
end