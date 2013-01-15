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
          size bigint NOT NULL DEFAULT 0,
          status ENUM('new', 'ready', 'error') NOT NULL DEFAULT 'new',
          time int DEFAULT NULL,
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), KEY (name), KEY (outer_id), KEY (time, status), KEY (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        SET NEW.time = UNIX_TIMESTAMP();
      }
      FC::DB.connect.query("CREATE TRIGGER fc_items_before_insert BEFORE INSERT on #{@prefix}items FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_before_update BEFORE UPDATE on #{@prefix}items FOR EACH ROW BEGIN #{proc} END")
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}storages (
          name varchar(255) NOT NULL DEFAULT '',
          host varchar(255) NOT NULL DEFAULT '',
          path text NOT NULL DEFAULT '',
          ur text NOT NULL DEFAULT '',
          size bigint NOT NULL DEFAULT 0,
          size_limit int NOT NULL DEFAULT 0,
          PRIMARY KEY (name), KEY (host)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        CREATE TRIGGER fc_storages_delete AFTER DELETE on #{@prefix}storages FOR EACH ROW BEGIN
          # update policy.storages on storage delete and update
          UPDATE #{@prefix}policy, 
            (SELECT #{@prefix}policy.id, GROUP_CONCAT(name) as storages FROM #{@prefix}policy, #{@prefix}storages WHERE FIND_IN_SET(name, storages)) as new_policy 
          SET #{@prefix}policy.storages = new_policy.storages WHERE #{@prefix}policy.id = new_policy.id;
        END
      }
      FC::DB.connect.query("CREATE TRIGGER fc_storages_after_delete AFTER DELETE on #{@prefix}storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_storages_after_update AFTER UPDATE on #{@prefix}storages FOR EACH ROW BEGIN #{proc} END")
      
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}items_storages (
          id int NOT NULL AUTO_INCREMENT,
          item_id int DEFAULT NULL,
          storage_name varchar(255) DEFAULT NULL,
          status ENUM('new', 'copy', 'error', 'ready', 'delete') NOT NULL DEFAULT 'new',
          time int DEFAULT NULL,
          PRIMARY KEY (id), KEY (item_id), KEY (storage_name), KEY (time, status), KEY (status),
          FOREIGN KEY (item_id) REFERENCES #{@prefix}items(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
          FOREIGN KEY (storage_name) REFERENCES #{@prefix}storages(name) ON UPDATE RESTRICT ON DELETE RESTRICT
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        SET NEW.time = UNIX_TIMESTAMP();
      }
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_before_insert BEFORE INSERT on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_before_update BEFORE UPDATE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc} END")
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}policy (
          id int NOT NULL AUTO_INCREMENT,
          storages text NOT NULL DEFAULT '',
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.storages on policy change
        SELECT GROUP_CONCAT(name) INTO @storages_list FROM #{@prefix}storages WHERE FIND_IN_SET(name, NEW.storages);
        SET NEW.storages = @storages_list;
      }
      FC::DB.connect.query("CREATE TRIGGER fc_policy_before_insert BEFORE INSERT on #{@prefix}policy FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_policy_before_update BEFORE UPDATE on #{@prefix}policy FOR EACH ROW BEGIN #{proc} END")
    end
  end
end
