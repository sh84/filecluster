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
    
    def self.get_speed_limits
      limits = {
        'all' => nil
      }
      list = self.get('daemon_copy_speed_per_host_limit', '').to_s
      limits.merge! Hash[list.split(';;').map{|v| v.split('::')}]
      limits.each{|host, val| limits[host] = val.to_f > 0 ? val.to_f : nil }
    end
    
    def self.set_speed_limit(host, val)
      limits = self.get_speed_limits
      limits[host.to_s] = val.to_f
      list = limits.map{|h, v| "#{h}::#{v}"}.join(';;')
      self.set('daemon_copy_speed_per_host_limit', list)
    end
    
    def self.get_current_speed_limit
      limits = self.get_speed_limits
      limit = limits[FC::Storage.curr_host]
      limit = limits['all'] unless limit
      limit
    end
  end
end
