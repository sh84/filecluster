# encoding: utf-8

module FC
  class CopyRule < DbBase
    set_table :copy_rules, 'rule, copy_storages'
    
    class << self
      attr_accessor :rules_cache_time, :get_rules_mutex, :copy_storages_cache_time, :get_copy_storages_mutex
    end
    @rules_cache_time = 20 # ttl for rules cache
    @copy_storages_cache_time = 20 # ttl for rule copy_storages
    @get_rules_mutex = Mutex.new
    @get_copy_storages_mutex = Mutex.new
    
    def self.all
      get_rules_mutex.synchronize do
        unless @all_rules_cache && Time.new.to_i - @get_all_rules_time.to_i < rules_cache_time
          @get_all_rules_time = Time.new.to_i
          @all_rules_cache = where("1")
        end
      end
      @all_rules_cache
    end
    
    def self.check_all(item_id, size, item_copies, name, tag, dir, src_storage)
      all.select do |r|
        r.check(item_id, size, item_copies, name, tag, dir, src_storage)
      end
    end
    
    # get available storage for copy
    def self.get_proper_storage_for_copy(options)
      rules = check_all(options[:item_id].to_i, options[:size].to_i, options[:item_copies].to_i, options[:name].to_s, options[:tag].to_s, options[:dir] ? true : false, options[:src_storage])
      result = nil
      rules.detect do |rule|
        result = FC::Storage.select_proper_storage_for_create(rule.get_copy_storages, options[:size].to_i, options[:exclude] || [])
      end
      result
    end
    
    def get_copy_storages
      self.class.get_copy_storages_mutex.synchronize do
        unless @copy_storages_cache && Time.new.to_i - @get_copy_storages_time.to_i < self.class.copy_storages_cache_time
          @get_copy_storages_time = Time.new.to_i
          names = copy_storages.to_s.split(',').map{|s| "'#{s}'"}.join(',')
          @copy_storages_cache = names.empty? ? [] : FC::Storage.where("name IN (#{names}) ORDER BY FIELD(name, #{names})")
        end
      end
      @copy_storages_cache
    end
    
    def check(item_id, size, item_copies, name, tag, dir, src_storage)
      return false unless rule
      $SELF = 4
      r = eval(rule)
      $SELF = 0
      r ? true : false
    end
    
    def test
      storage = FC::Storage.new(
        :id => 1,
        :name => 'test_storage',
        :host => 'test_host',
        :path => '/bla/bla',
        :url  => 'http://bla',
        :size => 1000,
        :size_limit => 9999,
        :check_time => Time.new.to_i, 
        :copy_storages => 'a,b,c'
      )
      check(3, 1, 1, 'test/item', 'tag', false, storage)
    end
  end
end
