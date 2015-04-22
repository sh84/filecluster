# encoding: utf-8
require 'shellwords'

def copy_speed_list
  FC::Var.get_speed_limits.each do |name, val|
    puts name.to_s+(val ? " - limit: #{val}Mbit" : " - unlimit")
  end
end

def copy_speed_add
  hosts = ['all'] + all_hosts
  puts "Add copy speed limit"
  begin
    host = stdin_read_val("Host (default #{FC::Storage.curr_host})", true).strip
    host = FC::Storage.curr_host if host.empty?
    puts "Host can be one of: #{hosts.join(', ')}" unless hosts.index(host)
  end until hosts.index(host)
  limit = stdin_read_val("Speed limit, Mbit/s (default 0 - unlimit)", true).to_f
  puts %Q{\nCopy speed limit
  Host:         #{host}
  Speed limit:  #{limit > 0 ? limit : 'unlimit'}}
  s = Readline.readline("Continue? (y/n) ", false).strip.downcase
  puts ""
  if s == "y" || s == "yes"
    begin
      FC::Var.set_speed_limit(host, limit)
    rescue Exception => e
      puts "Error: #{e.message}"
      exit
    end
    puts "ok"
  else
    puts "Canceled."
  end
end

def copy_speed_change
  if host = find_host
    puts "Change copy speed limit for host #{host}"
    curr_limit = FC::Var.get_speed_limits[host]
    limit = stdin_read_val("Speed limit, Mbit/s (now #{curr_limit ? curr_limit.to_s+', 0 to unlimit' : 'unlimit'})", true)
    puts limit.to_f
    puts limit == ''
    limit = limit == '' ? curr_limit : limit.to_f
    puts %Q{\nCopy speed limit
    Host:         #{host}
    Speed limit:  #{limit > 0 ? limit : 'unlimit'}}
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      begin
        FC::Var.set_speed_limit(host, limit)
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

def all_hosts
  FC::Storage.where('1').map(&:host).uniq
end

def find_host
  host = ARGV[2].to_s.strip
  puts "Storage with host #{host} not found." unless (['all'] + all_hosts).index(host)
  host
end
