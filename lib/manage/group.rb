# encoding: utf-8

require 'shellwords'

def group_list
  FC::Storage.where.to_a.group_by(&:shared_group).each do |group_name, storages|
    next if group_name.to_s.empty?
    group_info = storages.map { |s| "\t- #{s.name}: url_weight = #{s.url_weight}, write_weight = #{s.write_weight}" }
                         .join("\n")
    puts "Shared group \"#{group_name}\": \n#{group_info}"
  end
end

def group_change
  group_name = ARGV[2]
  shared_storages = FC::Storage.where('shared_group = ?', group_name).map(&:name).join(',')
  if shared_storages.empty?
    puts "Shared storages group with name \"#{group_name}\" was not found\nCancelled"
    exit
  end
  puts "Change shared group #{group_name}"
  new_name = stdin_read_val("name (now #{group_name})", true, group_name)
  new_shared_storages = stdin_read_val("shared storages (now #{shared_storages})", true, shared_storages)

  puts %(\nShared storages group change
name: #{new_name}
storages: #{new_shared_storages})

  unless group_storages_valid?(new_shared_storages)
    puts 'Cancelled'
    exit
  end

  group_confirm('Continue') do
    if new_name != group_name
      FC::DB.query(%(
        UPDATE #{FC::Storage.table_name}
        SET shared_group = '#{new_name}'
        WHERE shared_group = '#{group_name}'
      ))
    end
    group_sync_with_db(new_name, new_shared_storages) if new_shared_storages != shared_storages
  end
end

def group_add
  puts "Add new shared group"
  name = stdin_read_val('name', false)
  shared_storages = stdin_read_val('shared storages (comma separated, no spaces)', false)
  existing_groups = FC::DB.query("SELECT DISTINCT shared_group FROM #{FC::Storage.table_name} WHERE COALESCE(shared_group, '') <> ''")
                          .map { |row| row['shared_group'] }
  return if existing_groups.include?(name) &&
            !group_confirm("Shared storages group with name #{name} already exists, replace")
  puts %(\nNew shared storages group
name: #{name}
storages: #{shared_storages})

  unless group_storages_valid?(shared_storages)
    puts 'Cancelled'
    exit
  end

  group_confirm('Continue') do
    group_sync_with_db(name, shared_storages)
  end
end

def group_remove
  group_name = ARGV[2]
  group_confirm("Remove shared storages group \"#{group_name}\"") do
    group_sync_with_db(group_name, '')
  end
end

private

def group_confirm(msg)
  s = Readline.readline("#{msg}? (y/n) ", false).strip.downcase
  puts ''
  if %w[y yes].include?(s)
    yield if block_given?
    puts 'ok'
    true
  else
    puts 'Cancelled'
    false
  end
end

def group_sync_with_db(group_name, storage_list)
  db_storages = FC::Storage.where('shared_group = ?', group_name)
  list = storage_list.split(',')
  # remove storages from group which isn't in list
  db_storages.each do |s|
    if list.include?(s.name)
      list.delete(s.name)
      next
    end
    s.shared_group = nil
    s.save
  end

  # set new storages to group
  return unless list.any?
  FC::Storage.where("name in ('#{list.join("','")}')").each do |s|
    s.shared_group = group_name
    s.save
  end
end

def group_storages_valid?(storage_list)
  valid = true
  return if storage_list.to_s.empty?
  storages = []
  copy_storages = []
  FC::Storage.where("name in ('#{storage_list.split(',').join("','")}')").each do |s|
    storages << s.name
    copy_storages << s.copy_storages.to_s.split(',')
  end
  copy_storages.flatten!
  copy_storages.uniq!
  storages.each do |s|
    next unless copy_storages.include?(s)
    valid = false
    puts "Storage \"#{s}\" can not be used as copy storage within the same shared group!"
  end
  valid
end
