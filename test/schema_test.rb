require 'helper'
require 'manage/schema'
class SchemaTest < Test::Unit::TestCase
  class << self
    def startup
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM vars")
      FC::DB.query("DELETE FROM copy_rules")
      FC::DB.query("DELETE FROM storages")
    end
  end

  def teardown
    FC::DB.query("DELETE FROM policies")
    FC::DB.query("DELETE FROM vars")
    FC::DB.query("DELETE FROM copy_rules")
    FC::DB.query("DELETE FROM storages")
  end

  should 'create dump' do
    rule = FC::CopyRule.new(copy_storages: 'rec2-sda,rec3-sda', rule: 'size < 100')
    rule.save
    rule.reload
    storage = FC::Storage.new(
      name: 'rec1-sda',
      host: 'rec1',
      size: 0,
      size_limit: 100,
      dc: 'test',
      copy_storages: 'rec2-sda',
      url: '//host/disk/',
      url_weight: 1,
      write_weight: 2
    )
    storage.save
    storage.reload

    policy = FC::Policy.new(name: 'src', create_storages: 'rec1-sda', copies: 1, delete_deferred_time: 86400);
    policy.save
    policy.reload

    FC::Var.set('some_variable', 'value sample')
    FC::Var.set('awesome variable', 'awesome value')

    dump = create_dump
    assert_equal 1, dump[:storages].size
    FC::Storage.table_fields.each do |field|
      next if %w[check_time autosync_at].include? field # not dumping attrs
      assert_equal storage.send(field), dump[:storages][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    assert_equal 1, dump[:copy_rules].size
    FC::CopyRule.table_fields.each do |field|
      assert_equal rule.send(field), dump[:copy_rules][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    assert_equal 1, dump[:policies].size
    FC::Policy.table_fields.each do |field|
      assert_equal policy.send(field), dump[:policies][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    assert_equal 'value sample', dump[:vars][:some_variable]
    assert_equal 'awesome value', dump[:vars][:"awesome variable"]
  end

  should 'create db objects from dump' do
    schema = test_schema
    errors = create_or_update_schema(schema: schema, update: false)
    assert_equal 0, errors.size
    storage = FC::Storage.where.first
    policy = FC::Policy.where.first
    rule = FC::CopyRule.where.first
    FC::Storage.table_fields.each do |field|
      next if %w[check_time autosync_at].include? field # not dumping attrs
      assert_equal storage.send(field), schema[:storages][0][field.to_sym], "field \"#{field}\" not loaded correctly"
    end
    FC::CopyRule.table_fields.each do |field|
      assert_equal rule.send(field), schema[:copy_rules][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    FC::Policy.table_fields.each do |field|
      assert_equal policy.send(field), schema[:policies][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    assert_equal FC::Var.get('awesome variable'), schema[:vars][:"awesome variable"]
    assert_equal FC::Var.get(:some_variable), schema[:vars][:some_variable]
  end

  should 'apply props to objects from dump' do
    # create some objects
    rule = FC::CopyRule.new(copy_storages: 'rec2-sd1', rule: 'size < 100')
    rule.save

    storage = FC::Storage.new(
      name: 'rec1-sda_old',
      host: 'rec1',
      size: 10,
      size_limit: 200,
      dc: 'test_old',
      copy_storages: 'rec2-sda_old',
      url: '//host/disk_old/',
      url_weight: 3,
      write_weight: 4
    )
    storage.save

    policy = FC::Policy.new(name: 'src_old', create_storages: 'rec1-sda_old', copies: 1, delete_deferred_time: 86400);
    policy.save

    FC::Var.set('some_variable', 'original value')
    FC::Var.set('should fail variable', 'value') # this should be in errors

    schema = test_schema
    errors = create_or_update_schema(schema: schema, update: true)

    assert_equal 3, errors.size # storage, policy, var
    assert errors.include?("FC::Storage \"#{schema[:storages][0][:name]}\" not found")
    assert errors.include?('FC::Var "awesome variable" not found')
    assert errors.include?("FC::Policy \"#{schema[:policies][0][:name]}\" not found")
    
    # restore right names
    storage = FC::Storage.new(
      name: 'rec1-sda',
      host: 'rec1',
      size: 10,
      size_limit: 200,
      dc: 'test_old',
      copy_storages: 'rec2-sda_old',
      url: '//host/disk_old/',
      url_weight: 3,
      write_weight: 4
    )
    storage.save

    policy.name = 'src'
    policy.save

    FC::Var.set('awesome variable', 'old awesome value')

    errors = create_or_update_schema(schema: schema, update: true)

    assert_equal 0, errors.size
    
    storage.reload
    policy.reload
    rule.reload

    FC::Storage.table_fields.each do |field|
      next if %w[check_time autosync_at].include? field # not dumping attrs
      assert_equal storage.send(field), schema[:storages][0][field.to_sym], "field \"#{field}\" not loaded correctly"
    end
    FC::CopyRule.table_fields.each do |field|
      assert_equal rule.send(field), schema[:copy_rules][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    FC::Policy.table_fields.each do |field|
      assert_equal policy.send(field), schema[:policies][0][field.to_sym], "field \"#{field}\" not dumped correctly"
    end
    assert_equal FC::Var.get('awesome variable'), schema[:vars][:"awesome variable"]
  end

  def test_schema
    yaml = %(
---
:storages:
- :name: rec1-sda
  :host: rec1
  :dc: test
  :path: ''
  :url: "//host/disk/"
  :size: 0
  :size_limit: 100
  :copy_storages: rec2-sda
  :url_weight: 1
  :write_weight: 2
  :auto_size: 0
:policies:
- :name: src
  :create_storages: rec1-sda
  :copies: 1
  :delete_deferred_time: 86400
:copy_rules:
- :rule: size < 100
  :copy_storages: rec2-sda,rec3-sda
:vars:
  :awesome variable: 'awesome value'
  :some_variable: 'value sample')
    Psych.load(yaml)
  end
end
