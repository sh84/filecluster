# encoding: utf-8
require 'shellwords'

def autosync_list
  FC::Var.get_autosync.each do |name, val|
    puts name.to_s+(val.to_i > 0 ? " - every: #{val} seconds" : " - never")
  end
end

def autosync_add
  hosts = ['all'] + all_hosts
  puts 'Set autosync interval'
  begin
    host = stdin_read_val("Host (default #{FC::Storage.curr_host})", true).strip
    host = FC::Storage.curr_host if host.empty?
    puts "Host can be one of: #{hosts.join(', ')}" unless hosts.index(host)
  end until hosts.index(host)
  interval = stdin_read_val('Autosync interval, seconds (0 - never, empty = all)', true)
  confirm_autosync_set(host, interval)
end

def autosync_change
  return if (host = find_host).to_s.empty?
  puts "Change autosync interval for host #{host}"
  interval = FC::Var.get_autosync[host]
  txt = interval.to_s.empty? ? 'default (=all)' : nil
  txt = interval.to_i.zero? ? 'never' : "#{interval}" unless txt
  interval = stdin_read_val("Autosync interval, seconds (now #{txt}, 0 - never, empty = all)", true)
  confirm_autosync_set(host, interval)
end

private

def confirm_autosync_set(host, interval)
  txt = interval.to_s.empty? ? 'default (=all)' : nil
  txt = interval.to_i.zero? ? 'never' : interval unless txt
  puts %(\nAutosync interval
  Host:     #{host}
  Interval: #{txt})
  s = Readline.readline('Continue? (y/n) ', false).strip.downcase
  puts ''
  if %w[y yes].include?(s)
    begin
      FC::Var.set_autosync(host, interval.to_s.empty? ? interval : interval.to_i)
    rescue Exception => e
      puts "Error: #{e.message}"
      exit
    end
    puts 'ok'
  else
    puts 'Canceled.'
  end
end
