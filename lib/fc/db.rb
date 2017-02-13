require 'mysql2'
require 'psych'

module FC
  module DB
    class << self
      attr_accessor :options, :prefix, :err_counter, :no_active_record, :connect_block, :logger
    end

    def self.options_yml_path
      File.expand_path(File.dirname(__FILE__) + '../../../bin/db.yml')
    end

    def self.symbolize_keys(options)
      options.each_with_object({}) { |el, memo| memo[el[0].to_sym] = el[1] }
    end

    def self.connect_by_config(options)
      @options = symbolize_keys(options)
      @prefix = @options[:prefix].to_s if @options[:prefix]
      connection = Mysql2::Client.new(@options)
      @connect_block = nil
      @connects = {} unless @connects
      @connects[Thread.current.object_id] = connection
    end

    def self.connect_by_yml(options = {})
      db_options = symbolize_keys(Psych.load(File.read(options_yml_path)))
      connect_by_config(db_options.merge(symbolize_keys(options)))
    end

    def self.connect_by_active_record(options = {})
      if defined?(Octopus::Proxy) && ActiveRecord::Base.connection.is_a?(Octopus::Proxy)
        connection = ActiveRecord::Base.connection.select_connection.instance_variable_get(:@connection)
      else
        connection = ActiveRecord::Base.connection.instance_variable_get(:@connection)
      end
      @options = symbolize_keys(connection.query_options)
      @options.merge!(symbolize_keys(options))
      @prefix = @options[:prefix].to_s if @options[:prefix]
      @connect_block = nil
      @connects = {} unless @connects
      @connects[Thread.current.object_id] = connection
    end

    def self.lazy_connect(&block)
      @connect_block = block
    end

    def self.connect_by_block(options = {})
      connection = @connect_block.call
      @options = connection.query_options.clone.merge(symbolize_keys(options))
      @prefix = @options[:prefix].to_s if @options[:prefix]
      @connects = {} unless @connects
      @connects[Thread.current.object_id] = connection
      @connect_block = nil
    end

    def self.connect
      connect_by_block if @connect_block
      return nil unless @options
      connect_by_config(@options) if @options[:multi_threads] && !@connects[Thread.current.object_id]
      if @options[:multi_threads]
        @connects[Thread.current.object_id]
      else
        @connects.first && @connects.first[1]
      end
    end

    def self.connect!(options = {})
      close if @connects && @connects[Thread.current.object_id]
      if @connect_block
        connect_by_block(options)
      elsif options[:host] || options[:database] || options[:username] || options[:password]
        connect_by_config(options)
      elsif @options
        connect_by_config(@options.merge(symbolize_keys(options)))
      elsif !@no_active_record && defined?(ActiveRecord::Base) && ActiveRecord::Base.connection
        connect_by_active_record(options)
      else
        connect_by_yml(options)
      end
    end

    def self.reconnect
      close if connect
      connect_by_config(@options)
    end

    def self.close
      if @options[:multi_threads]
        if @connects[Thread.current.object_id]
          @connects[Thread.current.object_id].close
          @connects.delete(Thread.current.object_id)
        end
      else
        @connects.first[1].close
        @connects.clear
      end
    end

    # connect.query with deadlock solution
    def self.query(sql)
      t1 = Time.new.to_f
      r = FC::DB.connect.query(sql)
      t2 = Time.new.to_f
      @logger.debug(format('FC SQL (%.1fms) %s', (t2 - t1) * 1000, sql)) if @logger
      FC::DB.err_counter = 0
      r = r.each(:as => :hash) {} if r
      r
    rescue Mysql2::Error => e
      raise e if e.message =~ /You have an error in your SQL syntax/
      FC::DB.err_counter = FC::DB.err_counter.to_i + 1
      if FC::DB.err_counter > 5
        FC::DB.err_counter = 0
        raise "Too many mysql errors, #{e.message}"
      elsif e.message =~ /Deadlock found when trying to get lock/
        msg = "#{e.message} - retry"
        @logger ? @logger.error(msg) : puts(msg)
        sleep 0.1
        query(sql)
      elsif e.message =~ /Lost connection to MySQL server during query/
        msg = "#{e.message} - reconnect"
        @logger ? @logger.error(msg) : puts(msg)
        FC::DB.connect.ping
        sleep 0.1
        query(sql)
      elsif @options[:reconnect]
        msg = "#{e.message} - reconnect"
        @logger ? @logger.info(msg) : puts(msg)
        reconnect
        query(sql)
      else
        raise e
      end
    end

    def self.server_time
      FC::DB.query("SELECT UNIX_TIMESTAMP() as curr_time").first['curr_time'].to_i
    end

    def self.init_db(silent = false)
      FC::DB.query(%{
        CREATE TABLE #{@prefix}items (
          id bigint NOT NULL AUTO_INCREMENT,
          name varchar(1024) NOT NULL DEFAULT '',
          tag varchar(255) DEFAULT NULL,
          outer_id int DEFAULT NULL,
          policy_id int NOT NULL,
          dir tinyint(1) NOT NULL DEFAULT 0,
          size bigint NOT NULL DEFAULT 0,
          md5 varchar(32) DEFAULT NULL,
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
      FC::DB.query("CREATE TRIGGER fc_items_before_insert BEFORE INSERT on #{@prefix}items FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.query("CREATE TRIGGER fc_items_before_update BEFORE UPDATE on #{@prefix}items FOR EACH ROW BEGIN #{proc_time} END")

      FC::DB.query(%{
        CREATE TABLE #{@prefix}storages (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL DEFAULT '',
          host varchar(255) NOT NULL DEFAULT '',
          path varchar(2048) NOT NULL DEFAULT '',
          url varchar(2048) NOT NULL DEFAULT '',
          size bigint NOT NULL DEFAULT 0,
          size_limit bigint NOT NULL DEFAULT 0,
          check_time int DEFAULT NULL,
          copy_storages varchar(2048) NOT NULL DEFAULT '',
          PRIMARY KEY (id), UNIQUE KEY (name), KEY (host)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.create_storages on storage delete and update
        UPDATE #{@prefix}policies,
          (SELECT #{@prefix}policies.id, GROUP_CONCAT(#{@prefix}storages.name ORDER BY FIND_IN_SET(#{@prefix}storages.name, create_storages)) as storages FROM #{@prefix}policies LEFT JOIN #{@prefix}storages ON
            FIND_IN_SET(#{@prefix}storages.name, create_storages) GROUP BY #{@prefix}policies.id) as policy_create
        SET #{@prefix}policies.create_storages = policy_create.storages
        WHERE policy_create.id = #{@prefix}policies.id;
      }
      proc_update = %{
        IF OLD.name <> NEW.name THEN
          #{proc}
        END IF;
      }
      FC::DB.query("CREATE TRIGGER fc_storages_after_delete AFTER DELETE on #{@prefix}storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.query("CREATE TRIGGER fc_storages_after_update AFTER UPDATE on #{@prefix}storages FOR EACH ROW BEGIN #{proc_update} END")

      FC::DB.query(%{
        CREATE TABLE #{@prefix}policies (
          id int NOT NULL AUTO_INCREMENT,
          name varchar(255) NOT NULL DEFAULT '',
          create_storages varchar(2048) NOT NULL DEFAULT '',
          copies int NOT NULL DEFAULT 0,
          PRIMARY KEY (id), UNIQUE KEY (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      proc = %{
        # update policy.create_storages on policy change - guarantee valid policy.storages
        SELECT GROUP_CONCAT(name ORDER BY FIND_IN_SET(name, NEW.create_storages)) INTO @create_storages_list FROM #{@prefix}storages WHERE FIND_IN_SET(name, NEW.create_storages);
        SET NEW.create_storages = @create_storages_list;
      }
      FC::DB.query("CREATE TRIGGER fc_policies_before_insert BEFORE INSERT on #{@prefix}policies FOR EACH ROW BEGIN #{proc} END")
      FC::DB.query("CREATE TRIGGER fc_policies_before_update BEFORE UPDATE on #{@prefix}policies FOR EACH ROW BEGIN #{proc} END")

      FC::DB.query(%{
        CREATE TABLE #{@prefix}items_storages (
          id bigint NOT NULL AUTO_INCREMENT,
          item_id bigint DEFAULT NULL,
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
      FC::DB.query("CREATE TRIGGER fc_items_storages_before_insert BEFORE INSERT on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.query("CREATE TRIGGER fc_items_storages_before_update BEFORE UPDATE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.query("CREATE TRIGGER fc_items_storages_after_update AFTER UPDATE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc} END")
      FC::DB.query("CREATE TRIGGER fc_items_storages_after_insert AFTER INSERT on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_add} END")
      FC::DB.query("CREATE TRIGGER fc_items_storages_after_delete AFTER DELETE on #{@prefix}items_storages FOR EACH ROW BEGIN #{proc_del} END")

      FC::DB.query(%{
        CREATE TABLE #{@prefix}errors (
          id int NOT NULL AUTO_INCREMENT,
          item_id bigint DEFAULT NULL,
          item_storage_id bigint DEFAULT NULL,
          host varchar(255) DEFAULT NULL,
          message text DEFAULT NULL,
          time int DEFAULT NULL,
          PRIMARY KEY (id), KEY (item_id), KEY (item_storage_id), KEY (host), KEY (time)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      FC::DB.query("CREATE TRIGGER fc_errors_before_insert BEFORE INSERT on #{@prefix}errors FOR EACH ROW BEGIN #{proc_time} END")

      FC::DB.query(%{
        CREATE TABLE #{@prefix}copy_rules (
          id int NOT NULL AUTO_INCREMENT,
          copy_storages varchar(2048) NOT NULL DEFAULT '',
          rule text DEFAULT NULL,
          PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })

      FC::DB.query(%{
        CREATE TABLE #{@prefix}vars (
          name varchar(255) NOT NULL DEFAULT '',
          val varchar(255) NOT NULL DEFAULT '',
          descr text DEFAULT NULL,
          time int DEFAULT NULL,
          PRIMARY KEY (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci
      })
      FC::DB.query("CREATE TRIGGER fc_vars_before_insert BEFORE INSERT on #{@prefix}vars FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.query("CREATE TRIGGER fc_vars_before_update BEFORE UPDATE on #{@prefix}vars FOR EACH ROW BEGIN #{proc_time} END")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_cycle_time', val='30', descr='time between global daemon checks and storages available checks'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_global_wait_time', val='120', descr='time between runs global daemon if it does not running'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_tasks_copy_group_limit', val='1000', descr='select limit for copy tasks'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_tasks_delete_group_limit', val='10000', descr='select limit for delete tasks'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_tasks_copy_threads_limit', val='10', descr='copy tasks threads count limit for one storage'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_tasks_delete_threads_limit', val='10', descr='delete tasks threads count limit for one storage'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_copy_tasks_per_host_limit', val='10', descr='copy tasks count limit for one host'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_global_tasks_group_limit', val='1000', descr='select limit for create copy tasks'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_global_error_items_ttl', val='86400', descr='ttl for items with error status before delete'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_global_error_items_storages_ttl', val='86400', descr='ttl for items_storages with error status before delete'")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_restart_period', val='86400', descr='time between fc-daemon self restart'")

      FC::DB.migrations(silent)
    end

    def self.version
      return 1
    end

    def self.migrations(silent = false)
      next_version = FC::DB.query("SELECT val FROM #{FC::DB.prefix}vars WHERE name='db_version'").first['val'].to_i + 1 rescue 1
      while self.respond_to?("migrate_#{next_version}")
        puts "migrate to #{next_version}" unless silent
        self.send("migrate_#{next_version}")
        FC::DB.query("REPLACE #{FC::DB.prefix}vars SET val=#{next_version}, name='db_version'")
        next_version += 1
      end
    end

    def self.migrate_1
      FC::DB.query("ALTER TABLE #{@prefix}storages ADD COLUMN url_weight int NOT NULL DEFAULT 0")
      FC::DB.query("ALTER TABLE #{@prefix}storages ADD COLUMN write_weight int NOT NULL DEFAULT 0")
      FC::DB.query("INSERT INTO #{@prefix}vars SET name='daemon_copy_speed_per_host_limit', val='', descr='copy tasks speed limit for hosts, change via fc-manage copy_speed'")
    end

    def self.migrate_2
      FC::DB.query("ALTER TABLE #{@prefix}storages ADD COLUMN dc varchar(255) DEFAULT ''")
    end

    def self.migrate_3
      FC::DB.query("ALTER TABLE #{@prefix}items MODIFY COLUMN status ENUM('new', 'ready', 'error', 'delete', 'deferred_delete') NOT NULL DEFAULT 'new'")
      FC::DB.query("ALTER TABLE #{@prefix}policies ADD COLUMN delete_deferred_time int NOT NULL DEFAULT 0")
    end

    def self.migrate_4
      FC::DB.query("ALTER TABLE #{@prefix}storages ADD COLUMN size_type bigint(20) DEFAULT 0")
    end

  end
end
