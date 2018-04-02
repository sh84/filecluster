require "date"
require "daemon/base_thread"
require "daemon/check_thread"
require "daemon/global_daemon_thread"
require "daemon/run_tasks_thread"
require "daemon/update_tasks_thread"
require "daemon/copy_task_thread"
require "daemon/delete_task_thread"
require "daemon/autosync_thread"

def error(msg, options = {})
  $log.error(msg)
  FC::Error.new(options.merge(:host => FC::Storage.curr_host, :message => msg)).save
end

class << FC::Error
  def raise(msg, options = {})
    error(msg, options)
  end
end

def run_global_daemon
  $log.debug('Run global daemon check')
  timeout = FC::Var.get('daemon_global_wait_time', 120).to_i
  r = FC::DB.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  if !r || r['curr_time'].to_i - r['time'].to_i > timeout
    $log.debug('Set global daemon host to current')
    FC::Var.set('global_daemon_host', FC::Storage.curr_host)
    sleep 1
    r = FC::DB.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  end
  if r['val'] == FC::Storage.curr_host
    if !$global_daemon_thread || !$global_daemon_thread.alive?
      $log.debug("spawn GlobalDaemonThread")
      $global_daemon_thread = GlobalDaemonThread.new(timeout)
    end 
  elsif $global_daemon_thread && $global_daemon_thread.alive?
    $log.warn("Kill global daemon thread (new host = #{r['val']})")
    $global_daemon_thread.exit
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
  if !$update_tasks_thread || !$update_tasks_thread.alive?
    $log.debug("spawn UpdateTasksThread")
    $update_tasks_thread = UpdateTasksThread.new
  end
end

def run_tasks
  if !$run_tasks_thread || !$run_tasks_thread.alive?
    $log.debug("spawn RunTasksThread")
    $run_tasks_thread = RunTasksThread.new
  end
end

def autosync
  if !$autosync_thread || !$autosync_thread.alive?
    intervals = FC::Var.get_autosync
    storage_interval = intervals[FC::Storage.curr_host] || intervals['all']
    return if storage_interval.zero? # do not run aytosync
    storages = $storages.select do |s|
      s.autosync_at.to_i + storage_interval < Time.now.to_i
    end
    return unless storages.any?
    $log.debug("spawn AutosyncThread for storages #{storages.map(&:name).join(', ')}")
    $autosync_thread = AutosyncThread.new(storages)
  end
end