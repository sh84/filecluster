# encoding: utf-8
require 'shellwords'

def storages_list
  storages = FC::Storage.where("1 ORDER BY host")
  if storages.size == 0
    puts "No storages."
  else
    storages.each do |storage|
      str = " #{colorize_string(storage.dc, :blue)}\t#{colorize_string(storage.host, :yellow)} #{storage.name} #{size_to_human(storage.size)}/#{size_to_human(storage.size_limit)} "
      str += "#{(storage.free_rate*100).to_i}% free "
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
  DC:             #{storage.dc}
  Path:           #{storage.path} 
  Url:            #{storage.url}
  Url weight:     #{storage.url_weight}
  Write weight    #{storage.write_weight}
  Size:           #{size_to_human storage.size} (#{(storage.size_rate*100).to_i}%)
  Free:           #{size_to_human storage.free} (#{(storage.free_rate*100).to_i}%) 
  Size limit:     #{size_to_human storage.size_limit}
  Size type:      #{storage.auto_size? ? "Auto (min #{ size_to_human storage.auto_size })" : 'Static'}
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
  dc = stdin_read_val('DC')
  path = stdin_read_val('Path')
  url = stdin_read_val('Url')
  url_weight = stdin_read_val('URL weight', true).to_i
  write_weight = stdin_read_val('Write weight', true).to_i
  is_auto_size = %(y yes).include?(stdin_read_val('Auto size (y/n)?').downcase)
  if is_auto_size
    auto_size = human_to_size stdin_read_val('Minimal free disk space') {|val| "Minimal free disk space not is valid size." unless human_to_size(val) || human_to_size(val) < 1 }
    size_limit = 0
  else
    auto_size = 0
    size_limit = human_to_size stdin_read_val('Size limit') {|val| "Size limit not is valid size." unless human_to_size(val)}
  end

  copy_storages = stdin_read_val('Copy storages', true)
  storages = FC::Storage.where.map(&:name)
  copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip
  begin
    path = path +'/' unless path[-1] == '/'
    path = '/' + path unless path[0] == '/'
    storage = FC::Storage.new(:name => name, :dc => dc, :host => host, :path => path, :url => url, :size_limit => size_limit, :copy_storages => copy_storages, :url_weight => url_weight, :write_weight => write_weight, :auto_size => auto_size)
    print 'Calc current size.. '
    size = storage.file_size('', true)
    puts "ok"
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end

  if storage.auto_size?
    storage.size = size
    size_limit = storage.get_real_size
  end
  free = size_limit - size
  puts %Q{\nStorage
  Name:         #{name}
  DC:           #{dc}
  Host:         #{host} 
  Path:         #{path} 
  Url:          #{url}
  URL weight:   #{url_weight}
  Write weight: #{write_weight}
  Size:         #{size_to_human size} (#{(size.to_f*100 / size_limit).to_i}%)
  Free:         #{size_to_human free} (#{(free.to_f*100 / size_limit).to_i}%)
  Size type:    #{storage.auto_size? ? "Auto (min #{ size_to_human(auto_size) })" : 'Static' }
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
    FC::DB.reconnect
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
    dc = stdin_read_val("DC (now #{storage.dc})", true)
    host = stdin_read_val("Host (now #{storage.host})", true)
    path = stdin_read_val("Path (now #{storage.path})", true)
    url = stdin_read_val("Url (now #{storage.url})", true)
    url_weight = stdin_read_val("URL weight (now #{storage.url_weight})", true)
    write_weight = stdin_read_val("Write weight (now #{storage.write_weight})", true)
    is_auto_size = %(y yes).include?(stdin_read_val("Auto size (now #{storage.auto_size? ? 'yes' : 'no'})", true, storage.auto_size? ? 'yes' : 'no').downcase)
    if is_auto_size
      auto_size = human_to_size stdin_read_val("Minimal free disk space (now #{size_to_human(storage.auto_size)})", true, size_to_human(storage.auto_size)) {|val| "Minimal free disk space not is valid size." if !human_to_size(val) || human_to_size(val) < 1}
      size_limit = 0
    else
      auto_size = 0
      size_limit = stdin_read_val("Size (now #{size_to_human(storage.size_limit)})", true) {|val| "Size limit not is valid size." if !val.empty? && !human_to_size(val)}
    end
    copy_storages = stdin_read_val("Copy storages (now #{storage.copy_storages})", true)
    
    storage.dc = dc unless dc.empty?
    storage.host = host unless host.empty?
    if !path.empty? && path != storage.path
      path = path +'/' unless path[-1] == '/'
      path = '/' + path unless path[0] == '/'
      storage.path = path 
      print "Calc current size.. "
      storage.size = storage.file_size('', true)
      puts "ok"
    end
    storage.auto_size = auto_size
    size_limit = size_to_human(storage.get_real_size) if storage.auto_size?
    storage.url = url unless url.empty?
    storage.url_weight = url_weight.to_i unless url_weight.empty?
    storage.write_weight = write_weight.to_i unless write_weight.empty?
    storage.size_limit = human_to_size(size_limit) unless size_limit.empty?
    storages = FC::Storage.where.map(&:name)
    storage.copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip unless copy_storages.empty?
    
    puts %Q{\nStorage
    Name:          #{storage.name}
    DC:            #{storage.dc}
    Host:          #{storage.host} 
    Path:          #{storage.path} 
    Url:           #{storage.url}
    URL weight:    #{storage.url_weight}
    Write weight:  #{storage.write_weight}
    Size:          #{size_to_human storage.size} (#{(storage.size_rate*100).to_i}%)
    Free:          #{size_to_human storage.free} (#{(storage.free_rate*100).to_i}%)
    Size type:     #{storage.auto_size? ? "Auto (Min #{size_to_human auto_size})" : 'Static' }
    Size limit:    #{size_to_human storage.size_limit }
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
    init_console_logger
    manual_sync(storage, true)
    puts 'Done.'
  end
end

def storages_sync
  if storage = find_storage
    return puts "Storage #{storage.name} is not local." if storage.host != FC::Storage.curr_host
    puts "Synchronize (#{storage.name}) storage and file system (#{storage.path}).."
    s = Readline.readline('Continue? (y/n) ', false).strip.downcase
    puts ''
    if s == 'y' || s == 'yes'
      init_console_logger
      manual_sync(storage, false)
      s = Readline.readline('Update storage size? (y/n) ', false).strip.downcase
      storages_update_size if s == 'y' || s == 'yes'
    else
      puts "Canceled."
    end
  end
end

def manual_sync(storage, dry_run)
  syncer = Autosync.new(storage, dry_run)
  syncer.run
  puts "Deleted #{syncer.files_to_delete.size} files"
  puts "Deleted #{syncer.items_to_delete.size} items_storages"
  if (ARGV[3])
    File.open(ARGV[3], 'w') do |file|
      syncer.files_to_delete.each { |f| file.puts f }
    end
    puts "Save deleted files to #{ARGV[3]}"
  end

  if (ARGV[4])
    File.open(ARGV[4], 'w') do |file|
      syncer.items_to_delete.each { |item_storage_id| file.puts item_storage_id }
    end
    puts "Save deleted items_storages to #{ARGV[4]}"
  end
end

def storages_sync_info_old
  if storage = find_storage
    return puts "Storage #{storage.name} is not local." if storage.host != FC::Storage.curr_host
    puts "Get synchronization info for (#{storage.name}) storage and file system (#{storage.path}).."
    make_storages_sync(storage, false)
    puts "Done."
  end
end

def storages_sync_old
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

def init_console_logger
  require 'logger'
  $log = Logger.new(STDOUT)
  $log.level = Logger::DEBUG
  $log.formatter = proc { |severity, datetime, progname, msg|
    "[#{severity}]: #{msg}\n"
  }
end

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
      delete_files << path if File.file?(f) && path != 'healthcheck'
      process_storage_dir_sync.call(path+'/') if File.directory?(f)
    end
  end  
  process_storage_dir_sync.call
    
  # rm delete_files
  FC::DB.reconnect unless no_reconnect
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
