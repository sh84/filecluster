# encoding: utf-8

module FC
  class Var
    class << self
      attr_accessor :cache_time
    end
    @mutex = Mutex.new
    @cache_time = 120 # ttl for get_all
    @all_vars = {}
    
    def self.set(name, val)
      @mutex.synchronize do
        FC::DB.query("UPDATE #{FC::DB.prefix}vars SET val='#{Mysql2::Client.escape(val.to_s)}' WHERE name='#{Mysql2::Client.escape(name.to_s)}'")
        FC::DB.query("INSERT IGNORE INTO #{FC::DB.prefix}vars SET val='#{Mysql2::Client.escape(val.to_s)}', name='#{Mysql2::Client.escape(name.to_s)}'")
        @all_vars[name.to_s] = val.to_s
        @all_vars[name.to_sym] = val.to_s
      end
    end
    
    def self.get(name, default_value = nil)
      get_all[name] || default_value
    end
    
    def self.get_all
      @mutex.synchronize do
        if !@get_all_read_time || Time.new.to_i - @get_all_read_time > cache_time
          @all_vars = {}
          FC::DB.query("SELECT * FROM #{FC::DB.prefix}vars").each do |row|
            @all_vars[row['name']] = row['val']
            @all_vars[row['name'].to_sym] = row['val']
          end
          @get_all_read_time = Time.new.to_i
        end
      end
      @all_vars 
    end
  end
end
