def storages_list
  storages = FC::Storage.where("1 ORDER BY host")
  if storages.size == 0
    puts "No storages."
  else
    storages.each do |storage|
      str = "#{colorize_string(storage.host, :yellow)} #{storage.name} #{size_to_human(storage.size)}/#{size_to_human(storage.size_limit)} "
      str += "#{storage.up? ? colorize_string('UP', :green) : colorize_string('DOWN', :red)}"
      str += " #{storage.check_time_delay} seconds ago" if storage.check_time
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
    count = FC::DB.connect.query("SELECT count(*) as cnt FROM #{FC::ItemStorage.table_name} WHERE storage_name='#{Mysql2::Client.escape(storage.name)}'").first['cnt']
    puts %Q{Storage
  Name:           #{storage.name}
  Host:           #{storage.host} 
  Path:           #{storage.path} 
  Url:            #{storage.url}
  Size:           #{size_to_human storage.size}
  Size limit:     #{size_to_human storage.size_limit}
  Check time:     #{storage.check_time ? "#{Time.at(storage.check_time)} (#{storage.check_time_delay} seconds ago)" : ''}
  Status:         #{storage.up? ? colorize_string('UP', :green) : colorize_string('DOWN', :red)}
  Items storages: #{count}}
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
    print "Calc current size.. "
    size = storage.file_size('')
    puts "ok"
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
    begin
      storage.save
    rescue Exception => e
      puts "Error: #{e.message}"
      exit
    end
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
