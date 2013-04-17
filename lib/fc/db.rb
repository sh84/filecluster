require 'mysql2'

module FC
  module DB
    class << self; attr_accessor :options, :prefix end
    
    def self.connect_by_config(options)
      @options = options.clone
      @options[:port] = options[:port].to_i if options[:port]
      @prefix = options[:prefix].to_s if options[:prefix]
      @connects = {}
      @connects[Thread.current.object_id] = Mysql2::Client.new(@options)
    end
    
    def self.connect
      if @options[:multi_threads]
        @connects[Thread.current.object_id] ||= Mysql2::Client.new(@options)
      else
        @connects.first[1]
      end
    end
    
    def self.connect=(connect, options = {})
      self.connect_by_config connect.query_options.merge(options).merge(:as => :hash)
    end
    
    def self.close
      if @options[:multi_threads]
        if @connects[Thread.current.object_id]
          @connects[Thread.current.object_id].close
          @connects.delete(Thread.current.object_id)
        end
      else
        @connects.first[1].close
      end
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
          PRIMARY KEY (id), UNIQUE KEY (name(255), policy_id), 
          KEY (outer_id), KEY (time, status), KEY (status, policy_id, copies), KEY (copies, status, policy_id)
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
          size_limit bigint NOT NULL DEFAULT 0,
          check_time int DEFAULT NULL,
          copy_id int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), UNIQUE KEY (name), KEY (host)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.create_storages and policy.copy_storages on storage delete and update
        UPDATE #{@prefix}policies, 
          (SELECT #{@prefix}policies.id, GROUP_CONCAT(#{@prefix}storages.name ORDER BY FIND_IN_SET(#{@prefix}storages.name, create_storages)) as storages FROM #{@prefix}policies LEFT JOIN #{@prefix}storages ON 
            FIND_IN_SET(#{@prefix}storages.name, create_storages) GROUP BY #{@prefix}policies.id) as policy_create,
          (SELECT #{@prefix}policies.id, GROUP_CONCAT(#{@prefix}storages.name ORDER BY FIND_IN_SET(#{@prefix}storages.name, copy_storages)) as storages FROM #{@prefix}policies LEFT JOIN #{@prefix}storages ON 
            FIND_IN_SET(#{@prefix}storages.name, copy_storages) GROUP BY #{@prefix}policies.id) as policy_copy
        SET 
          #{@prefix}policies.create_storages = policy_create.storages, 
          #{@prefix}policies.copy_storages = policy_copy.storages
        WHERE policy_create.id = #{@prefix}policies.id AND policy_copy.id = #{@prefix}policies.id;
      }
      proc_update = %{
        IF OLD.name <> NEW.name THEN 
          #{proc}
        END IF;
      }
      FC::DB.connect.query("CREATE TRIGGER fc_storages_after_delete AFTER DELETE on #{@prefix}storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.connect.query("CREATE TRIGGER fc_storages_after_update AFTER UPDATE on #{@prefix}storages FOR EACH ROW BEGIN #{proc_update} END")
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}policies (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL DEFAULT '',
          create_storages text NOT NULL DEFAULT '',
          copy_storages text NOT NULL DEFAULT '',
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), UNIQUE KEY (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.create_storages and policy.copy_storages on policy change - guarantee valid policy.storages
        SELECT GROUP_CONCAT(name ORDER BY FIND_IN_SET(name, NEW.create_storages)) INTO @create_storages_list FROM #{@prefix}storages WHERE FIND_IN_SET(name, NEW.create_storages);
        SELECT GROUP_CONCAT(name ORDER BY FIND_IN_SET(name, NEW.copy_storages)) INTO @copy_storages_list FROM #{@prefix}storages WHERE FIND_IN_SET(name, NEW.copy_storages);
        SET NEW.create_storages = @create_storages_list;
        SET NEW.copy_storages = @copy_storages_list;
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
          PRIMARY KEY (id), UNIQUE KEY (item_id, storage_name), KEY (storage_name), KEY (time, status), KEY (status, storage_name),          
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
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}errors (
          id int NOT NULL AUTO_INCREMENT,
          item_id int DEFAULT NULL,
          item_storage_id int DEFAULT NULL,
          host varchar(255) DEFAULT NULL,
          message varchar(255) DEFAULT NULL,
          time int DEFAULT NULL,
          PRIMARY KEY (id), KEY (item_id), KEY (item_storage_id), KEY (host), KEY (time)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      FC::DB.connect.query("CREATE TRIGGER fc_errors_before_insert BEFORE INSERT on #{@prefix}errors FOR EACH ROW BEGIN #{proc_time} END")
      
      FC::DB.connect.query(%{
        CREATE TABLE #{@prefix}vars (
          name varchar(255) DEFAULT NULL,
          val varchar(255) DEFAULT NULL,
          time int DEFAULT NULL,
          PRIMARY KEY (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      FC::DB.connect.query("CREATE TRIGGER fc_vars_before_insert BEFORE INSERT on #{@prefix}vars FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.connect.query("CREATE TRIGGER fc_vars_before_update BEFORE UPDATE on #{@prefix}vars FOR EACH ROW BEGIN #{proc_time} END")
    end
  end
end
