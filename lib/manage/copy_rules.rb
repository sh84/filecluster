# encoding: utf-8
require 'shellwords'

def copy_rules_list
  rules = FC::CopyRule.where("1 ORDER BY id")
  if rules.size == 0
    puts "No rules."
  else
    rules.each do |rule|
      puts "##{rule.id}, copy storages: #{rule.copy_storages}, rule: #{rule.rule}"
    end
  end
end

def copy_rules_show
  if rule = find_rule
    #count = FC::DB.query("SELECT count(*) as cnt FROM #{FC::ItemStorage.table_name} WHERE storage_name='#{Mysql2::Client.escape(storage.name)}'").first['cnt']
    puts %Q{Rule
  Id:             #{rule.id}
  Copy storages:  #{rule.copy_storages}
  Rule:           #{rule.rule}}
  end
end

def copy_rules_add
  puts "Add copy rule"
  copy_storages = stdin_read_val('Copy storages')
  storages = FC::Storage.where.map(&:name)
  copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip
  rule_str = stdin_read_val('Rule')
  
  begin
    rule = FC::CopyRule.new(:rule => rule_str, :copy_storages => copy_storages)
    rule.test
  rescue Exception => e
    puts "Error: #{e.message}"
    exit
  end
  puts %Q{\nRule
  Copy storages:  #{rule.copy_storages}
  Rule:           #{rule.rule}}
  s = Readline.readline("Continue? (y/n) ", false).strip.downcase
  puts ""
  if s == "y" || s == "yes"
    begin
      rule.save
    rescue Exception => e
      puts "Error: #{e.message}"
      exit
    end
    puts "ok"
  else
    puts "Canceled."
  end
end

def copy_rules_rm
  if rule = find_rule
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      rule.delete
      puts "ok"
    else
      puts "Canceled."
    end
  end
end

def copy_rules_change
  if rule = find_rule
    puts "Change rule #{rule.id}"
    copy_storages = stdin_read_val("Copy storages (now #{rule.copy_storages})", true)
    storages = FC::Storage.where.map(&:name)
    rule.copy_storages = copy_storages.split(',').select{|s| storages.member?(s.strip)}.join(',').strip unless copy_storages.empty?
    rule_str = stdin_read_val("Rule (now #{rule.rule})", true)
    rule.rule = rule_str unless rule_str.empty?
    
    puts %Q{\nRule
    Id:             #{rule.id}
    Copy storages:  #{rule.copy_storages}
    Rule:           #{rule.rule}}
    s = Readline.readline("Continue? (y/n) ", false).strip.downcase
    puts ""
    if s == "y" || s == "yes"
      begin
        rule.test
        rule.save
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

def find_rule
  id = ARGV[2]
  rule = FC::CopyRule.where('id = ?', id).first
  puts "Rule #{id} not found." unless rule
  rule
end
