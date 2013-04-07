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
  r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  if !r || r['curr_time'].to_i - r['time'].to_i > timeout
    FC::DB.connect.query("REPLACE #{FC::DB.prefix}vars SET val='#{FC::Storage.curr_host}', name='global_daemon_host'")
    sleep 1
    r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  end
  if r['val'] == FC::Storage.curr_host
    $global_daemon_thread = GlobalDaemonThread.new(timeout) if !$global_daemon_thread || !$global_daemon_thread.alive?
  else
    if $global_daemon_thread
      $log.warn("Kill global daemon thread (new host = #{r['host']})")
      $global_daemon_thread.exit
    end 
  end
end

def update_storages
  $storages = FC::Storage.where('host = ?', FC::Storage.curr_host)
end

def storages_check
  $check_threads.each do |storage_name, thread|
    if thread.alive?
      error "Storage #{storage_name} check timeout"
      thread.exit
    end
  end
  $storages.each do|storage| 
    $check_threads[storage.name] = CheckThread.new(storage.name)
  end
end

def update_tasks
  return if $storages.length == 0
  
  def check_tasks(type)
    storages_names = $storages.map{|storage| "'#{storage.name}'"}.join(',')
    cond = "storage_name in (#{storages_names}) AND status='#{type.to_s}'"
    ids = $tasks.map{|storage_name, storage_tasks| storage_tasks.select{|task| task[:action] == type}}.
      flatten.map{|task| task[:item_storage].id}
    cond << "AND id not in (#{ids.join(',')})" if (ids.length > 0)
    FC::ItemStorage.where(cond).each do |item_storage|
      $tasks[item_storage.name] = [] unless $tasks[item_storage.name]
      $tasks[item_storage.name] << {:action => type, :item_storage => item_storage}
    end
  end
  
  check_tasks(:delete)
  check_tasks(:copy)
end

def run_tasks
  $storages.each do |storage|
    thread = $tasks_threads[storage.name]
    if (!thread || !thread.alive?) && $tasks[storage.name] && $tasks[storage.name].size > 0 
      $tasks_threads[storage.name] = TaskThread.new(storage.name)
    end
  end
end





