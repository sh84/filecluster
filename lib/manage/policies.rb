def policies_list
  policies = FC::Policy.where
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
    count = FC::DB.connect.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} WHERE policy_id = #{policy.id}").first['cnt']
    puts %Q{Policy
  ID:         #{policy.id}
  Storages:   #{policy.storages}
  Copies:     #{policy.copies}
  Items:      #{count}}
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
