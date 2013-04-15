def policies_list
  policies = FC::Policy.where
  if policies.size == 0
    puts "No storages."
  else
    policies.each do |policy|
      puts "##{policy.id} #{policy.name}, create storages: #{policy.create_storages}, copy storages: #{policy.copy_storages}, copies: #{policy.copies}"
    end
  end
end

def policies_show
  if policy = find_policy
    count = FC::DB.connect.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} WHERE policy_id = #{policy.id}").first['cnt']
    puts %Q{Policy
  ID:               #{policy.id}
  Name:             #{policy.name}
  Create storages:  #{policy.create_storages}
  Copy storages:    #{policy.copy_storages}
  Copies:           #{policy.copies}
  Items:            #{count}}
  end
end

def policies_add
  puts "Add Policy"
  name = stdin_read_val('Name')
  create_storages = stdin_read_val('Create storages')
  copy_storages = stdin_read_val('Copy storages')
  copies = stdin_read_val('Copies').to_i
  
  storages = FC::Storage.where.map(&:name)
  create_storages = create_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip
  copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip
  
  begin
    policy = FC::Policy.new(:name => name, :create_storages => create_storages, :copy_storages => copy_storages, :copies => copies)
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end
  puts %Q{\nPolicy
  Name:             #{name}
  Create storages:  #{create_storages}
  Copy storages:    #{copy_storages} 
  Copies:           #{copies}}
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
    copy_storages = stdin_read_val("Copy storages (now #{policy.copy_storages})", true)
    copies = stdin_read_val("Copies (now #{policy.copies})", true)
    
    storages = FC::Storage.where.map(&:name)
    create_storages = create_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip unless create_storages.empty?
    copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip unless copy_storages.empty?
        
    policy.name = name unless name.empty?
    policy.create_storages = name unless create_storages.empty?
    policy.copy_storages = name unless copy_storages.empty?
    policy.copies = copies.to_i unless copies.empty?
    
    puts %Q{\nStorage
    Name:             #{policy.name}
    Create storages:  #{policy.create_storages}
    Copy storages:    #{policy.copy_storages} 
    Copies:           #{policy.copies}}
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