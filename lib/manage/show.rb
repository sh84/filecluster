def show_current_host
 puts "Current host: #{FC::Storage.curr_host}"
end

def show_global_daemon
  r = FC::DB.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
  if r 
    puts "Global daemon run on #{r['val']}\nLast run #{r['curr_time']-r['time']} seconds ago."
  else
    puts "Global daemon is not runnning."
  end
end

def show_errors
  count = ARGV[2] || 10
  errors = FC::Error.where("1 ORDER BY id desc LIMIT #{count.to_i}")
  if errors.size == 0
    puts "No errors."
  else
    errors.each do |error|
      puts "#{Time.at(error.time)} item_id: #{error.item_id}, item_storage_id: #{error.item_storage_id}, host: #{error.host}, message: #{error.message}"
    end
  end
end

def show_host_info
  host = ARGV[2] || FC::Storage.curr_host
  storages = FC::Storage.where("host = ?", host)
  if storages.size == 0
    puts "No storages."
  else
    puts "Info for host #{host}"
    storages.each do |storage|
      counts = FC::DB.query("SELECT status, count(*) as cnt FROM #{FC::ItemStorage.table_name} WHERE storage_name='#{Mysql2::Client.escape(storage.name)}' GROUP BY status")
      str = "#{storage.name} #{size_to_human(storage.size)}/#{size_to_human(storage.size_limit)} "
      str += "#{storage.up? ? colorize_string('UP', :green) : colorize_string('DOWN', :red)}"
      str += " #{storage.check_time_delay} seconds ago" if storage.check_time
      str += "\n"
      counts.each do |r|
        str += "   Items storages #{r['status']}: #{r['cnt']}\n"
      end
      puts str
    end
  end
end

def show_items_info
  puts "Items by status:"
  counts = FC::DB.query("SELECT status, count(*) as cnt FROM #{FC::Item.table_name} WHERE 1 GROUP BY status")
  counts.each do |r|
    puts "   #{r['status']}: #{r['cnt']}"
  end
  puts "Items storages by status:"
  counts = FC::DB.query("SELECT status, count(*) as cnt FROM #{FC::ItemStorage.table_name} WHERE 1 GROUP BY status")
  counts.each do |r|
    puts "   #{r['status']}: #{r['cnt']}"
  end
  count = FC::DB.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} as i, #{FC::Policy.table_name} as p WHERE i.policy_id = p.id AND i.copies > 0 AND i.copies < p.copies AND i.status = 'ready'").first['cnt']
  puts "Items to copy: #{count}"
  count = FC::DB.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} as i, #{FC::Policy.table_name} as p WHERE i.policy_id = p.id AND i.copies > p.copies AND i.status = 'ready'").first['cnt']
  puts "Items to delete: #{count}"
end