require 'psych'
def schema_create
  unless ARGV[2]
    puts 'config file not set'
    exit(1)
  end
  force = ARGV[3].to_s == 'force'
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
    schema[:copy_rules].each do |pl|
      errors << "CopyRule \"#{pl[:rule]}\" already exists\n" if FC::CopyRule.where('rule = ?', pl[:rule]).any?
    end
    existing_vars = FC::Var.get_all
    schema[:vars].keys.each do |v|
      errors << "Var \"#{v}\" already exists\n" if existing_vars.include?(v)
    end

    unless errors.empty?
      puts errors
      exit(1)
    end
  end
  errors = create_or_update_schema(schema: schema, update: false)
  puts errors.join("\n") if errors && errors.any?
end

def schema_apply
  schema = load_schema_file
  apply_connection(schema[:connection])
  errors = create_or_update_schema(schema: schema, update: true)
  puts errors.join("\n") if errors && errors.any?
end

def schema_dump
  dump = create_dump
  if ARGV[2]
    File.write ARGV[2], Psych.dump(dump)
  else
    puts Psych.dump(dump)
  end
end

def create_or_update_schema(schema:, update:)
  errors = []
  errors << apply_entity(klass: FC::Storage, items: schema[:storages], update_only: update)
  errors << apply_entity(klass: FC::Policy, items: schema[:policies], update_only: update)
  errors << apply_entity(klass: FC::CopyRule, items: schema[:copy_rules], key_field: :rule, update_only: update)
  errors << apply_vars(vars: schema[:vars], update_only: update)
  errors.flatten
end

def create_dump
  schema = { }
  schema[:storages] = FC::Storage.where.map(&:dump)
  schema[:policies] = FC::Policy.where.map(&:dump)
  schema[:copy_rules] = FC::CopyRule.where.map(&:dump)
  schema[:vars] = FC::Var.get_all.select { |k, _| k.is_a? Symbol }
  schema[:connection] = FC::DB.instance_variable_get('@options')
  schema
end

def load_schema_file
  schema = Psych.load(File.read(ARGV[2]))
  schema[:storages] ||= []
  schema[:policies] ||= []
  schema[:copy_rules] ||= []
  schema[:vars] ||= {}
  schema
end

def apply_connection(options)
  return unless options
  FC::DB.close
  FC::DB.connect_by_config(options)
  FC::DB.connect.ping
  File.write(FC::DB.options_yml_path, Psych.dump(options))
end

def apply_vars(vars:, update_only: false)
  errors = []
  existing_vars = FC::Var.get_all
  vars.each do |k, v|
    if !existing_vars.keys.include?(k) && update_only
      errors << "FC::Var \"#{k}\" not found"
      next
    end
    FC::Var.set(k, v)
  end
  errors
end

def apply_entity(klass:, items:, update_only: false, key_field: :name)
  errors = []
  return errors unless items
  items.each do |item|
    begin
      result = klass.apply!(data: item, update_only: update_only, key_field: key_field)
      errors << result if result.is_a? String
    rescue => save_error
      errors << "Error while saving #{klass} \"#{item[key_field]}\": #{save_error}"
    end
  end
  errors
end
