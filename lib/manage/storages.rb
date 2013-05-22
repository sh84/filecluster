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
  if storage = find_storage
    count = FC::DB.query("SELECT count(*) as cnt FROM #{FC::ItemStorage.table_name} WHERE storage_name='#{Mysql2::Client.escape(storage.name)}'").first['cnt']
    puts %Q{Storage
  Name:           #{storage.name}
  Host:           #{storage.host} 
  Path:           #{storage.path} 
  Url:            #{storage.url}
  Size:           #{size_to_human storage.size}
  Size limit:     #{size_to_human storage.size_limit}
  Copy id:        #{storage.copy_id}
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
  copy_id = stdin_read_val('Copy id').to_i
  begin
    path = path +'/' unless path[-1] == '/'
    path = '/' + path unless path[0] == '/'
    storage = FC::Storage.new(:name => name, :host => host, :path => path, :url => url, :size_limit => size_limit, :copy_id => copy_id)
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
  Size limit: #{size_to_human size_limit}
  Copy id:    #{copy_id}}
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
  if storage = find_storage
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

def storages_update_size
  if storage = find_storage
    print "Calc current size.. "
    size = storage.file_size('')
    storage.size = size
    begin
      storage.save
    rescue Exception => e
      puts "Error: #{e.message}"
      exit
    end
    puts "ok"
  end
end

def storages_change
  if storage = find_storage
    puts "Change storage #{storage.name}"
    host = stdin_read_val("Host (now #{storage.host})", true)
    path = stdin_read_val("Path (now #{storage.path})", true)
    url = stdin_read_val("Url (now #{storage.url})", true)
    size_limit = stdin_read_val("Size (now #{size_to_human(storage.size_limit)})", true) {|val| "Size limit not is valid size." if !val.empty? && !human_to_size(val)}
    copy_id = stdin_read_val("Copy id (now #{storage.copy_id})", true)
    
    storage.host = host unless host.empty?
    if !path.empty? && path != storage.path
      path = path +'/' unless path[-1] == '/'
      path = '/' + path unless path[0] == '/'
      storage.path = path 
      print "Calc current size.. "
      storage.size = storage.file_size('')
      puts "ok"
    end
    storage.url = url unless url.empty?
    storage.size_limit = human_to_size(size_limit) unless size_limit.empty?
    storage.copy_id = copy_id.to_i
    
    puts %Q{\nStorage
    Name:       #{storage.name}
    Host:       #{storage.host} 
    Path:       #{storage.path} 
    Url:        #{storage.url}
    Size:       #{size_to_human storage.size}
    Size limit: #{size_to_human storage.size_limit}
    Copy id:    #{copy_id}}
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
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
end

private

def find_storage
  name = ARGV[2]
  storage = FC::Storage.where('name = ?', name).first
  puts "Storage #{name} not found." if !storage
  storage
end
