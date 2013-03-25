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
          name varchar(1024) NOT NULL DEFAULT '',
          tag varchar(255) DEFAULT NULL,
          outer_id int DEFAULT NULL,
          policy_id int NOT NULL,
          dir tinyint(1) NOT NULL DEFAULT 0,
          size bigint NOT NULL DEFAULT 0,
          status ENUM('new', 'ready', 'error', 'delete') NOT NULL DEFAULT 'new',
          time int DEFAULT NULL,
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), KEY (name), KEY (outer_id), KEY (time, status), KEY (status)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc_time = %{
        SET NEW.time = UNIX_TIMESTAMP();
      }
      FC::DB.connect.query("CREATE TRIGGER fc_items_before_insert BEFORE INSERT on #{@prefix}items FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_before_update BEFORE UPDATE on #{@prefix}items FOR EACH ROW BEGIN #{proc_time} END")
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}storages (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL DEFAULT '',
          host varchar(255) NOT NULL DEFAULT '',
          path text NOT NULL DEFAULT '',
          url text NOT NULL DEFAULT '',
          size bigint NOT NULL DEFAULT 0,
          size_limit int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), UNIQUE KEY (name), KEY (host)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.storages on storage delete and update
        UPDATE #{@prefix}policies, 
          (SELECT #{@prefix}policies.id, GROUP_CONCAT(name) as storages FROM #{@prefix}policies LEFT JOIN #{@prefix}storages ON FIND_IN_SET(name, storages) GROUP BY #{@prefix}policies.id) as new_policy
        SET #{@prefix}policies.storages = new_policy.storages WHERE #{@prefix}policies.id = new_policy.id;
      }
      FC::DB.connect.query("CREATE TRIGGER fc_storages_after_delete AFTER DELETE on #{@prefix}storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_storages_after_update AFTER UPDATE on #{@prefix}storages FOR EACH ROW BEGIN #{proc} END")
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}policies (
          id int NOT NULL AUTO_INCREMENT,
          storages text NOT NULL DEFAULT '',
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.storages on policy change - guarantee valid policy.storages
        SELECT GROUP_CONCAT(name) INTO @storages_list FROM #{@prefix}storages WHERE FIND_IN_SET(name, NEW.storages);
        SET NEW.storages = @storages_list;
      }
      FC::DB.connect.query("CREATE TRIGGER fc_policies_before_insert BEFORE INSERT on #{@prefix}policies FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_policies_before_update BEFORE UPDATE on #{@prefix}policies FOR EACH ROW BEGIN #{proc} END")
      
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
        SELECT status, copies, size INTO @item_status, @item_copies, @item_size FROM #{@prefix}items WHERE id = NEW.item_id;
        SET @curr_copies = (SELECT count(*) FROM #{@prefix}items_storages WHERE item_id = NEW.item_id AND status <> 'delete');
        SET @curr_copies_ready = (SELECT count(*) FROM #{@prefix}items_storages WHERE item_id = NEW.item_id AND status = 'ready');
        # calc item.copies
        IF @curr_copies <> @item_copies THEN 
          UPDATE #{@prefix}items SET copies=@curr_copies WHERE id = NEW.item_id;
        END IF;
        # check error status
        IF @item_status <> 'new' AND @item_status <> 'delete' AND @curr_copies_ready = 0 THEN 
          UPDATE #{@prefix}items SET status='error' WHERE id = NEW.item_id;
        END IF;
        # check ready status
        IF @curr_copies_ready > 0 THEN 
          UPDATE #{@prefix}items SET status='ready' WHERE id = NEW.item_id;
        END IF;
      }
      proc_add = %{
        #{proc}
        UPDATE #{@prefix}storages SET size=size+@item_size WHERE name = NEW.storage_name;
      }
      proc_del = %{
        #{proc.gsub('NEW', 'OLD')}
        UPDATE #{@prefix}storages SET size=size-@item_size WHERE name = OLD.storage_name;
      }
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_before_insert BEFORE INSERT on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_before_update BEFORE UPDATE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_after_update AFTER UPDATE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_after_insert AFTER INSERT on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_add} END")
      FC::DB.connect.query("CREATE TRIGGER fc_items_storages_after_delete AFTER DELETE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_del} END")
    end
  end
end
