def var_list
  vars = FC::DB.query("SELECT * FROM #{FC::DB.prefix}vars WHERE descr IS NOT NULL")
  if vars.size == 0
    puts "No vars."
  else
    vars.each do |var|
      puts var['name']
    end
  end
end

def var_show
  if var = find_var
    puts %Q{Var
  Name:         #{var['name']}
  Value:        #{var['val']}
  Description:  #{var['descr']}}
  end
end

def var_change
  if var = find_var
    puts "Change var #{var['name']}"
    val = stdin_read_val("Value (now #{var['val']})")
        
    puts %Q{\nVar
    Name:         #{var['name']}
    Value:        #{val}}
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      begin
        FC::Var.set(var['name'], val)
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

def find_var
  var = FC::DB.query("SELECT * FROM #{FC::DB.prefix}vars WHERE descr IS NOT NULL AND name='#{Mysql2::Client.escape(ARGV[2].to_s)}'").first
  puts "Var #{ARGV[2]} not found." unless var
  var
end