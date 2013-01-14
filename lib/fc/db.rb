require 'mysql2'

module FC
  module DB
    class << self; attr_accessor :connect, :prefix end
    
    
    def DB.connect_by_config(options)
      options[:port] = options[:port].to_i if options[:port]
      @connect = Mysql2::Client.new(options)
      @prefix = options[:prefix].to_s
    end
    
    def DB.init_db
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}items (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL DEFAULT '',
          tag varchar(255) DEFAULT NULL,
          outer_id int DEFAULT NULL,
          policy_id int NOT NULL,
          dir tinyint(1) NOT NULL DEFAULT 0,
          status varchar(255) NOT NULL DEFAULT 'new',
          time int DEFAULT NULL,
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), KEY (name), KEY (outer_id), KEY (time, status), KEY (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      FC::DB.connect.query(%{
        CREATE TRIGGER #{@prefix}items_time_proc BEFORE INSERT on #{@prefix}items FOR EACH ROW
        begin
          if (new.time is null) then
            set new.time = UNIX_TIMESTAMP();
           end if;
         end
       })
       
    end
  end
end
