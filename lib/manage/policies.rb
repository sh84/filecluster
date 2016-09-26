def policies_list
  policies = FC::Policy.where
  if policies.size == 0
    puts "No storages."
  else
    policies.each do |policy|
      puts "##{policy.id} #{policy.name}, create storages: #{policy.create_storages}, copies: #{policy.copies}"
    end
  end
end

def policies_show
  if policy = find_policy
    count = FC::DB.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} WHERE policy_id = #{policy.id}").first['cnt']
    puts %Q{Policy
  ID:                   #{policy.id}
  Name:                 #{policy.name}
  Create storages:      #{policy.create_storages}
  Copies:               #{policy.copies}
  Delete deferred time: #{policy.delete_deferred_time}
  Items:                #{count}}
  end
end

def policies_add
  puts "Add Policy"
  name = stdin_read_val('Name')
  create_storages = stdin_read_val('Create storages')
  copies = stdin_read_val('Copies').to_i
  delete_deferred_time = stdin_read_val('Delete deferred time').to_i
  
  storages = FC::Storage.where.map(&:name)
  create_storages = create_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip
  
  begin
    policy = FC::Policy.new(
      :name => name,
      :create_storages => create_storages,
      :copies => copies,
      :delete_deferred_time => delete_deferred_time
    )
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end
  puts %Q{\nPolicy
  Name:                 #{name}
  Create storages:      #{create_storages}
  Copies:               #{copies}
  Delete deferred time: #{delete_deferred_time}}
  s = Readline.readline("Continue? (y/n) ", false).strip.downcase
  puts ""
  if s == "y" || s == "yes"
    begin
      policy.save
    rescue Exception => e
      puts "Error: #{e.message}"
      exit
    end
    puts "ok"
  else
    puts "Canceled."
  end
end

def policies_rm
  if policy = find_policy
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

def policies_change
  if policy = find_policy
    puts "Change policy ##{policy.id} #{policy.name}"
    name = stdin_read_val("Name (now #{policy.name})", true)
    create_storages = stdin_read_val("Create storages (now #{policy.create_storages})", true)
    copies = stdin_read_val("Copies (now #{policy.copies})", true)
    delete_deferred_time = stdin_read_val("Delete deferred time (now #{policy.delete_deferred_time})", true)
    
    storages = FC::Storage.where.map(&:name)
    create_storages = create_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip unless create_storages.empty?
        
    policy.name = name unless name.empty?
    policy.create_storages = create_storages unless create_storages.empty?
    policy.copies = copies.to_i unless copies.empty?
    
    puts %Q{\nStorage
    Name:                 #{policy.name}
    Create storages:      #{policy.create_storages}
    Copies:               #{policy.copies}
    Delete deferred time: #{policy.delete_deferred_time}}
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      begin
        policy.save
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

def find_policy
  policy = FC::Policy.where('id = ?', ARGV[2]).first
  policy = FC::Policy.where('name = ?', ARGV[2]).first unless policy
  puts "Policy #{ARGV[2]} not found." unless policy
  policy
end
