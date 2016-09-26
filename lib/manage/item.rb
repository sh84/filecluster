def item_info
  name = ARGV[2] || ''
  name = name.gsub('_', '\\_').gsub('%', '\\%').gsub('?', '_').gsub('*', '%')
  count = FC::DB.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} WHERE name like '#{name}'").first['cnt']
  puts "Find #{count} items:"
  if (count > 1)
    items = FC::DB.query("SELECT name FROM #{FC::Item.table_name} WHERE name like '#{name}' ORDER BY id DESC LIMIT 100")
    items.each{|r| puts r["name"]}
    puts "Last item:"
  end
  item = FC::DB.query("SELECT i.id, i.name, tag, outer_id, p.name as policy, size, status, time, i.copies FROM #{FC::Item.table_name} as i, #{FC::Policy.table_name} as p WHERE i.name like '#{name}' AND p.id=policy_id ORDER BY i.id DESC LIMIT 1").first
  if item
    item_storages = FC::DB.query("SELECT storage_name, status, time FROM #{FC::ItemStorage.table_name} WHERE item_id=#{item["id"]}")
    puts %Q{
    ID:               #{item["id"]}
    Outer id:         #{item["outer_id"]}
    Name:             #{item["name"]}
    Status:           #{item["status"]}
    Tag:              #{item["tag"]}
    Policy:           #{item["policy"]}
    Size:             #{size_to_human(item["size"])}
    Time:             #{Time.at(item["time"])}
    Copies:           #{item["copies"]}}
    if item_storages.size > 0
      puts "Item on storages:"
      item_storages.each do |r|
        s = "    #{r["storage_name"]}:"
        s << " "*[(22-s.length), 1].max
        s << case r["status"]
          when "ready" then colorize_string("ready", :green)
          when "error" then colorize_string("ready", :red)
          else r["status"]
        end
        s << " - #{Time.at(r["time"])}"
        puts s
      end
    end
  end
end

def item_add
  path = ARGV[2] || ''
  name = ARGV[3] || ''
  policy = FC::Policy.where('id = ?', ARGV[4]).first
  policy = FC::Policy.where('name = ?', ARGV[4]).first unless policy
  puts "Policy #{ARGV[4]} not found." unless policy
  
  if policy
    begin
      item = FC::Item.create_from_local(path, name, policy, :tag => 'fc-manage-add', :replace => true, :not_local => true)
      item_storage = item.get_item_storages.first
      storage = FC::Storage.where('name = ?', item_storage.storage_name).first
      puts "Saved as #{storage.name+':'+storage.path+item.name}"
    rescue Exception => e
      puts e.message
    end
  end
end

def item_add_local
  storage = FC::Storage.where('name = ?', ARGV[2]).first
  puts "Storage #{ARGV[2]} not found." unless storage
  name = ARGV[3] || ''
  policy = FC::Policy.where('id = ?', ARGV[4]).first
  policy = FC::Policy.where('name = ?', ARGV[4]).first unless policy
  puts "Policy #{ARGV[4]} not found." unless policy
  tag = ARGV[5] || 'fc-manage-add-local'
  outer_id = ARGV[6]
  
  if policy && storage
    if name.index(storage.path) == 0
      path = name
      name = name.sub(storage.path, '/').gsub('//', '/')
    else
      path = (storage.path+name).gsub('//', '/')
    end
    begin
      item = FC::Item.create_from_local(path, name, policy, :tag => tag, :outer_id => outer_id, :replace => true)
      item_storage = item.get_item_storages.first
      storage = FC::Storage.where('name = ?', item_storage.storage_name).first
      puts "Saved as #{storage.name+':'+storage.path+item.name}"
    rescue Exception => e
      puts e.message
    end
  end
end

def item_rm
  name = ARGV[2] || ''
  item = FC::Item.where('name = ?', name).first
  if !item
    puts "Item #{name} not found."
  else
    s = Readline.readline('Immediate delete? (y/n) ', false).strip.downcase
    puts ''
    immediate_delete = s == 'y' || s == 'yes'
    s = Readline.readline('Delete? (y/n) ', false).strip.downcase
    puts ''
    if s == 'y' || s == 'yes'
      immediate_delete ? item.immediate_delete : item.mark_deleted
      puts 'ok'
    else
      puts 'Canceled.'
    end
  end
end
