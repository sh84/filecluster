# encoding: utf-8

module FC
  class Var
    class << self
      attr_accessor :cache_time
    end
    @cache_time = 120 # ttl for get_all
    @all_vars = {}
    
    def self.set(name, val)
      @all_vars[name] = val.to_s
      @all_vars[name.to_sym] = val.to_s
      FC::DB.query("REPLACE #{FC::DB.prefix}vars SET val='#{Mysql2::Client.escape(val.to_s)}', name='#{Mysql2::Client.escape(name.to_s)}'")
    end
    
    def self.get(name, force = false)
      return @all_vars[name] if get_all[name] && !force
      FC::DB.query("SELECT * FROM #{FC::DB.prefix}vars WHERE name='#{Mysql2::Client.escape(name.to_s)}'").first['val']
    end
    
    def self.get_all
      if !@get_all_read_time || Time.new.to_i - @get_all_read_time > cache_time
        @all_vars = {}
        FC::DB.query("SELECT * FROM #{FC::DB.prefix}vars").each do |row|
          @all_vars[row['name']] = row['val']
          @all_vars[row['name'].to_sym] = row['val']
        end
      end
      @all_vars 
    end
  end
end
