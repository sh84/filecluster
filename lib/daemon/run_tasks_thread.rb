class RunTasksThread < BaseThread
  def go
    $log.debug('Run tasks')
    run_tasks(:delete)
    run_tasks(:copy)
  end
  
  def run_tasks(type)
    tasks = (type == :copy ? $tasks_copy : $tasks_delete)
    tasks_threads = (type == :copy ? $tasks_copy_threads : $tasks_delete_threads)
    $storages.each do |storage|
      tasks_threads[storage.name] = [] unless tasks_threads[storage.name]
      tasks_threads[storage.name].delete_if {|thread| !thread.alive?}
      tasks_count = tasks[storage.name] ? tasks[storage.name].size : 0
      threads_count = tasks_threads[storage.name].count
      thread_avg_performance = 0
      thread_avg_performance = tasks_threads[storage.name].inject(0){|sum, thread| sum+thread[:tasks_processed]} / threads_count if threads_count > 0
      thread_avg_performance = 10 if thread_avg_performance < 10
      max_threads = FC::Var.get("daemon_tasks_#{type}_threads_limit", 10).to_i
      
      run_threads_count = (tasks_count/thread_avg_performance.to_f).ceil
      run_threads_count = max_threads if run_threads_count > max_threads
      run_threads_count = run_threads_count - threads_count
      run_threads_count = 0 if run_threads_count < 0
      
      $log.debug("#{storage.name} #{type} tasks_count: #{tasks_count}, threads_count: #{threads_count}, avg_performance: #{thread_avg_performance}, run_threads_count: #{run_threads_count}")
      tasks_threads[storage.name].each{|thread| thread[:tasks_processed] = 0}
      run_threads_count.times do
        tasks_threads[storage.name] << (type == :copy ? CopyTaskThread.new(storage.name) : DeleteTaskThread.new(storage.name))
      end
    end
  end
end