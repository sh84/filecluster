require 'psych'
def schema_create
  unless ARGV[2]
    puts 'config file not set'
    exit(1)
  end
  force = ARGV[3].to_s == '--force'
  schema = load_schema_file

  apply_connection(schema[:connection])
  # check existing objects
  unless force
    errors = ''
    schema[:storages].each do |cs|
      errors << "Storage \"#{cs[:name]}\" already exists\n" if FC::Storage.where('name = ?', cs[:name]).any?
    end
    schema[:policies].each do |pl|
      errors << "Policy \"#{pl[:name]}\" already exists\n" if FC::Policy.where('name = ?', pl[:name]).any?
    end
    unless errors.empty?
      puts errors
      exit(1)
    end
  end

  apply_storages(storages: schema[:storages])
  apply_policies(policies: schema[:policies])
end

def schema_apply
  schema = load_schema_file
  apply_connection(schema[:connection])
  apply_storages(storages: schema[:storages], update_only: true)
  apply_policies(policies: schema[:policies], update_only: true)
end

def schema_dump
  schema = {
    connection: {},
    storages: [],
    policies: []
  }
  FC::Storage.where.each do |s|
    schema[:storages] << {
      name: s.name,
      host: s.host,
      dc: s.dc,
      path: s.path,
      url: s.url,
      copy_storages: s.copy_storages,
      url_weight: s.url_weight,
      write_weight: s.write_weight,
      auto_size: s.auto_size,
      size_limit: s.size_limit,
      size: s.size
    }
  end

  FC::Policy.where.each do |pl|
    schema[:policies] << {
      name: pl.name,
      create_storages: pl.create_storages.split(','),
      copies: pl.copies,
      delete_deferred_time: pl.delete_deferred_time
    }
  end

  schema[:connection].merge!(FC::DB.instance_variable_get('@options'))
  if ARGV[2]
    File.write ARGV[2], Psych.dump(schema)
  else
    puts Psych.dump(schema)
  end
end

private

def load_schema_file
  schema = Psych.load(File.read(ARGV[2]))
  schema[:storages] ||= []
  schema[:policies] ||= []
  schema
end

def apply_connection(options)
  return unless options
  FC::DB.close
  FC::DB.connect_by_config(options)
  FC::DB.connect.ping
  File.write(FC::DB.options_yml_path, Psych.dump(options))
end

def apply_storages(storages:, update_only: false)
  storages.each do |cs|
    storage = FC::Storage.where('name = ?', cs[:name]).first
    if storage.nil? && update_only
      puts "Storage \"#{cs[:name]}\" not found"
      next
    end

    storage ||= FC::Storage.new
    storage.dc = cs[:dc] if cs[:dc]
    storage.path = cs[:path] if cs[:path]
    storage.url = cs[:url] if cs[:url]
    storage.write_weight = cs[:write_weight].to_i if cs[:write_weight]
    storage.url_weight = cs[:url_weight].to_i if cs[:url_weight]
    storage.auto_size = cs[:auto_size].to_i if cs[:auto_size]
    storage.copy_storages = cs[:copy_storages] if cs[:copy_storages]

    unless storage.name
      storage.name = cs[:name]
      storage.size = cs[:size].to_i if cs[:size]
      storage.size_limit = cs[:size_limit].to_i if cs[:size_limit]
      storage.host = cs[:host] if cs[:host]
    end
    begin
      storage.save
    rescue => save_error
      puts "Error while saving storage \"#{storage.name}\": #{save_error}"
    end
  end
end

def apply_policies(policies:, update_only: false)
  return unless policies
  policies.each do |pl|
    policy = FC::Policy.where('name = ?', pl[:name]).first
    if policy.nil? && update_only
      puts "Policy \"#{pl[:name]}\" not found"
      next
    end

    policy ||= FC::Policy.new
    policy.name = pl[:name] unless policy.name
    policy.create_storages = pl[:create_storages].join(',') if pl[:create_storages]
    policy.copies = pl[:copies].to_i if pl[:copies]
    policy.delete_deferred_time = pl[:delete_deferred_time].to_i if pl[:delete_deferred_time]
    begin
      policy.save
    rescue => save_error
      puts "Error while saving policy \"#{policy.name}\": #{save_error}"
    end
  end
end
