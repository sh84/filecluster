require "date"
require "daemon/base_thread"
require "daemon/global_daemon_thread"
require "daemon/check_thread"
require "daemon/task_thread"

def error(msg, options = {})
  $log.error(msg)
  FC::Error.new(options.merge(:host => FC::Storage.curr_host, :message => msg)).save
end

class << FC::Error
  def raise(msg, options = {})
    error(msg, options)
  end
end

def run_global_daemon(timeout)
  $log.debug('Run global daemon check')
  r = FC::DB.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  if !r || r['curr_time'].to_i - r['time'].to_i > timeout
    $log.debug('Set global daemon host to current')
    FC::DB.query("REPLACE #{FC::DB.prefix}vars SET val='#{FC::Storage.curr_host}', name='global_daemon_host'")
    sleep 1
    r = FC::DB.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  end
  if r['val'] == FC::Storage.curr_host
    if !$global_daemon_thread || !$global_daemon_thread.alive?
      $log.debug("spawn GlobalDaemonThread")
      $global_daemon_thread = GlobalDaemonThread.new(timeout)
    end 
  else
    if $global_daemon_thread
      $log.warn("Kill global daemon thread (new host = #{r['host']})")
      $global_daemon_thread.exit
    end 
  end
end

def update_storages
  $log.debug('Update storages')
  $all_storages = FC::Storage.where
  $storages = $all_storages.select{|s| s.host == FC::Storage.curr_host}
end

def storages_check
  $log.debug('Run storages check')
  $check_threads.each do |storage_name, thread|
    if thread.alive?
      error "Storage #{storage_name} check timeout"
      thread.exit
    end
  end
  $storages.each do|storage| 
    $log.debug("spawn CheckThread for #{storage.name}")
    $check_threads[storage.name] = CheckThread.new(storage.name)
  end
end

def update_tasks
  $log.debug('Update tasks')
  return if $storages.length == 0
  
  def check_tasks(type)
    storages_names = $storages.map{|storage| "'#{storage.name}'"}.join(',')
    cond = "storage_name in (#{storages_names}) AND status='#{type.to_s}'"
    ids = $tasks.map{|storage_name, storage_tasks| storage_tasks.select{|task| task[:action] == type}}.
      flatten.map{|task| task[:item_storage].id}
    ids += $curr_tasks.select{|task| task[:action] == type}
      
    cond << "AND id not in (#{ids.join(',')})" if (ids.length > 0)
    cond << "LIMIT 1000"
    FC::ItemStorage.where(cond).each do |item_storage|
      $tasks[item_storage.storage_name] = [] unless $tasks[item_storage.storage_name]
      $tasks[item_storage.storage_name] << {:action => type, :item_storage => item_storage}
      $log.debug("task add: type=#{type}, item_storage=#{item_storage.id}")
    end
  end
  
  check_tasks(:delete)
  check_tasks(:copy)
end

def run_tasks
  $log.debug('Run tasks')
  $storages.each do |storage|
    $tasks_threads[storage.name] = [] unless $tasks_threads[storage.name]
    $tasks_threads[storage.name].delete_if {|thread| !thread.alive?}
    tasks_count = $tasks[storage.name] ? $tasks[storage.name].size : 0
    threads_count = $tasks_threads[storage.name].count
    # 10 tasks per thread, maximum 3 tasks
    run_threads_count = (tasks_count/10.0).ceil - threads_count
    run_threads_count = 3 if run_threads_count > 3
    $log.debug("tasks_count: #{tasks_count}, threads_count: #{threads_count}, run_threads_count: #{run_threads_count}")
    run_threads_count.times do
      $log.debug("spawn TaskThread for #{storage.name}") 
      $tasks_threads[storage.name] << TaskThread.new(storage.name)
    end
  end
end
