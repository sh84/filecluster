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
  r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  if !r || r['curr_time'].to_i - r['time'].to_i > timeout
    $log.debug('Set global daemon host to current')
    FC::DB.connect.query("REPLACE #{FC::DB.prefix}vars SET val='#{FC::Storage.curr_host}', name='global_daemon_host'")
    sleep 1
    r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
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
  $storages = FC::Storage.where('host = ?', FC::Storage.curr_host)
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
    $curr_task.map{|storage_name, task| ids << task[:item_storage].id if task && task[:action] == type}
      
    cond << "AND id not in (#{ids.join(',')})" if (ids.length > 0)
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
    thread = $tasks_threads[storage.name]
    if (!thread || !thread.alive?) && $tasks[storage.name] && $tasks[storage.name].size > 0
      $log.debug("spawn TaskThread for #{storage.name}") 
      $tasks_threads[storage.name] = TaskThread.new(storage.name)
    end
  end
end
