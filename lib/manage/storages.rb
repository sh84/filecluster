# encoding: utf-8
require 'shellwords'

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
  Copy storages:  #{storage.copy_storages}
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
  copy_storages = stdin_read_val('Copy storages')
  storages = FC::Storage.where.map(&:name)
  copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip
  begin
    path = path +'/' unless path[-1] == '/'
    path = '/' + path unless path[0] == '/'
    storage = FC::Storage.new(:name => name, :host => host, :path => path, :url => url, :size_limit => size_limit, :copy_storages => copy_storages)
    print "Calc current size.. "
    size = storage.file_size('', true)
    puts "ok"
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end
  puts %Q{\nStorage
  Name:         #{name}
  Host:         #{host} 
  Path:         #{path} 
  Url:          #{url}
  Size:         #{size_to_human size}
  Size limit:   #{size_to_human size_limit}
  Copy storages #{copy_storages}}
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
    FC::DB.close
    print "Calc current size.. "
    size = storage.file_size('', true)
    storage.size = size
    FC::DB.connect
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
    copy_storages = stdin_read_val("Copy storages (now #{storage.copy_storages})", true)
    
    storage.host = host unless host.empty?
    if !path.empty? && path != storage.path
      path = path +'/' unless path[-1] == '/'
      path = '/' + path unless path[0] == '/'
      storage.path = path 
      print "Calc current size.. "
      storage.size = storage.file_size('', true)
      puts "ok"
    end
    storage.url = url unless url.empty?
    storage.size_limit = human_to_size(size_limit) unless size_limit.empty?
    storages = FC::Storage.where.map(&:name)
    storage.copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip unless copy_storages.empty?
    
    puts %Q{\nStorage
    Name:          #{storage.name}
    Host:          #{storage.host} 
    Path:          #{storage.path} 
    Url:           #{storage.url}
    Size:          #{size_to_human storage.size}
    Size limit:    #{size_to_human storage.size_limit}
    Copy storages: #{storage.copy_storages}}
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

def storages_sync_info
  if storage = find_storage
    return puts "Storage #{storage.name} is not local." if storage.host != FC::Storage.curr_host
    puts "Get synchronization info for (#{storage.name}) storage and file system (#{storage.path}).."
    make_storages_sync(storage, false)
    puts "Done."
  end
end

def storages_sync
  if storage = find_storage
    return puts "Storage #{storage.name} is not local." if storage.host != FC::Storage.curr_host
    puts "Synchronize (#{storage.name}) storage and file system (#{storage.path}).."
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      make_storages_sync(storage, true)
      puts "Synchronize done."
      FC::DB.connect
      storages_update_size
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

def make_storages_sync(storage, make_delete, silent = false, no_reconnect = false)
  # get all items for storage
  puts "Getting all items from DB" unless silent
  db_items = {}
  FC::DB.query("SELECT i.name, ist.id, ist.status FROM #{FC::Item.table_name} as i, #{FC::ItemStorage.table_name} as ist WHERE ist.item_id = i.id AND ist.storage_name = '#{storage.name}'").each do |row|
    name = row['name'].sub(/\/$/, '').sub(/^\//, '').strip
    path = ''
    name.split('/').each do |dir|
      path << dir
      db_items[path] = [false, path == name ? row['id'].to_i : nil, row['status']]
      path << '/'
    end
  end
  FC::DB.close unless no_reconnect
  
  # walk on all storage folders and files
  puts "Getting all files" unless silent
  delete_files = []
  process_storage_dir_sync = lambda do |dir = ''|
    Dir.glob(storage.path+dir+'*').each do |f|
      path = f.sub(storage.path, '')
      if db_items[path]
        db_items[path][0] = true
        next if db_items[path][1] && db_items[path][2] != 'delete'
      end
      delete_files << path if File.file?(f)
      process_storage_dir_sync.call(path+'/') if File.directory?(f)
    end
  end  
  process_storage_dir_sync.call
    
  # rm delete_files
  FC::DB.connect unless no_reconnect
  if make_delete
    puts "Deleting files" unless silent
    delete_files.each do |f|
      # check in DB again
      next if FC::DB.query("SELECT ist.id FROM #{FC::Item.table_name} as i, #{FC::ItemStorage.table_name} as ist WHERE ist.item_id = i.id AND ist.storage_name = '#{storage.name}' AND i.name='#{f}' AND ist.status<>'delete'").first      
      path = storage.path+f
      File.delete(path) rescue nil
    end
    puts "Deleted #{delete_files.count} files" unless silent
  end
  
  # delete non synchronize items_storages
  puts "Deleting items from DB" unless silent
  count = 0  
  db_items.values.each do |item|
    if !item[0] && item[1] || item[2] == 'delete' && item[1]
      count += 1
      FC::DB.query("DELETE FROM #{FC::ItemStorage.table_name} WHERE id=#{item[1]}") if make_delete
    end
  end
  FC::DB.close unless no_reconnect
  puts "Deleted #{count} items_storages" unless silent
  
  # delete empty folders
  count = `find #{storage.path.shellescape} -empty -type d`.split("\n").count
  `find #{storage.path.shellescape} -empty -type d -delete` if make_delete
  puts "Deleted #{count} empty folders" unless silent
  
  if (ARGV[3])
    File.open(ARGV[3], 'w') do |file|
      delete_files.each do |f|
        file.puts storage.path+f
      end
    end
    puts "Save deleted files to #{ARGV[3]}" unless silent
  end
  
  if (ARGV[4])
    File.open(ARGV[4], 'w') do |file|
      db_items.values.each do |item|
        file.puts item[1] if !item[0] && item[1] || item[2] == 'delete' && item[1]
      end
    end
    puts "Save deleted items_storages to #{ARGV[4]}" unless silent
  end
end
