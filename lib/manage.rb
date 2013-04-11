require 'readline'

def show_current_host
 puts "Current host: #{FC::Storage.curr_host}"
end

def show_global_daemon
  r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
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


def storages_list
  storages = FC::Storage.where("1 ORDER BY host")
  if storages.size == 0
    puts "No storages."
  else
    storages.each do |storage|
      str = "#{colorize_string(storage.host, :yellow)} #{storage.name} #{size_to_human(storage.size)}/#{size_to_human(storage.size_limit)} "
      str += "#{storage.up? ? colorize_string('UP', :green) : colorize_string('DOWN', :red)}"
      str += "#{storage.check_time_delay} seconds ago" if storage.check_time
      puts str
    end
  end
end

def storages_show
  name = ARGV[2]
  storage = FC::Storage.where('name = ?', name).first
  if !storage
    puts "Storage #{name} not found."
  else
    puts %Q{Storage
  Name:       #{storage.name}
  Host:       #{storage.host} 
  Path:       #{storage.path} 
  Url:        #{storage.url}
  Size:       #{size_to_human storage.size}
  Size limit: #{size_to_human storage.size_limit}
  Check time: #{storage.check_time ? "#{Time.at(storage.check_time)} (#{check_time_delay} seconds ago)" : ''}
  Status:     #{storage.up? ? colorize_string('UP', :green) : colorize_string('DOWN', :red)}}
  end
end

def storages_add
  host = FC::Storage.curr_host
  puts "Add storage to host #{host}"
  name = stdin_read_val('Name')
  path = stdin_read_val('Path')
  url = stdin_read_val('Url')
  size_limit = human_to_size stdin_read_val('Size limit') {|val| "Size limit not is valid size." unless human_to_size(val)}
  begin
    storage = FC::Storage.new(:name => name, :host => host, :path => path, :url => url, :size_limit => size_limit)
    size = storage.file_size('')
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end
  puts %Q{\nStorage
  Name:       #{name}
  Host:       #{host} 
  Path:       #{path} 
  Url:        #{url}
  Size:       #{size_to_human size}
  Size limit: #{size_to_human size_limit}}
  s = Readline.readline("Continue? (y/n) ", false).strip.downcase
  puts ""
  if s == "y" || s == "yes"
    storage.size = size
    storage.save
    puts "ok"
  else
    puts "Canceled."
  end
end

def storages_rm
  name = ARGV[2]
  storage = FC::Storage.where('name = ?', name).first
  if !storage
    puts "Storage #{name} not found."
  else
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      storage.delete
      puts "ok"
    else
      puts "Canceled."
    end
  end
end


def policies_list
  policies = FC::Policy.where("1 ORDER BY host")
  if policies.size == 0
    puts "No storages."
  else
    policies.each do |policy|
      puts "##{policy.id} storages: #{policy.storages}, copies: #{policy.copies}"
    end
  end
end

def policies_show
  id = ARGV[2]
  policy = FC::Policy.where('id = ?', id).first
  if !policy
    puts "Policy ##{id} not found."
  else
    puts %Q{Policy
  ID:         #{policy.id}
  Storages:   #{policy.storages}
  Copies:     #{policy.copies}}
  end
end

def policies_add
  puts "Add Policy"
  storages = stdin_read_val('Storages')
  copies = stdin_read_val('Copies').to_i
  begin
    policy = FC::Policy.new(:storages => storages, :copies => copies)
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end
  puts %Q{\nPolicy
  Storages:   #{storages} 
  Copies:     #{copies}}
  s = Readline.readline("Continue? (y/n) ", false).strip.downcase
  puts ""
  if s == "y" || s == "yes"
    policy.save
    puts "ok"
  else
    puts "Canceled."
  end
end

def policies_rm
  id = ARGV[2]
  policy = FC::Policy.where('id = ?', id).first
  if !policy
    puts "Policy ##{id} not found."
  else
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      policy.delete
      puts "ok"
    else
      puts "Canceled."
    end
  end
end