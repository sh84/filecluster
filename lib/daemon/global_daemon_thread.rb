class GlobalDaemonThread < BaseThread
  def go(timeout)
    $log.info("Start global daemon thread with timeout=#{timeout}")
    while true do
      exit if $exit_signal
      sleep timeout.to_f/2
      exit if $exit_signal
      
      r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
      if r['val'] == FC::Storage.curr_host
        FC::DB.connect.query("UPDATE #{FC::DB.prefix}vars SET val='#{FC::Storage.curr_host}' WHERE name='global_daemon_host'")
      else
        $log.info("Exit from GlobalDaemonThread: global daemon already running on #{r['val']}")
        FC::DB.close
        exit
      end
      
      make_item_copies
      
      #периодическая проверка на item со статусом delete, последним обновлением дольше суток (NOW - time > 86400) и без связанных is - удаление таких из базы
      #периодически удалять (проставлять статус delete) для лиших is (число копий больше необходимого)
    end
  end
  
  # make item copies by policy
  def make_item_copies
    $log.debug("GlobalDaemonThread: make_item_copies")
    
    all_storages = FC::Storage.where
    all_policies = FC::Policy.where
    
    # policies.get_storages => all_policies.select
    all_policies.each do |policy|
      metaclass = class << policy; self; end
      metaclass.send(:define_method, :get_copy_storages) do
        @copy_storages_cache ||= self.copy_storages.split(',').map{|storage_name| all_storages.detect{|s| storage_name == s.name} }
      end
    end
    
    sql = "SELECT i.id as item_id, i.size, i.copies as item_copies, GROUP_CONCAT(ist.storage_name ORDER BY ist.id) as storages, p.id as policy_id, p.copies as policy_copies "+
      "FROM #{FC::Item.table_name} as i, #{FC::Policy.table_name} as p, #{FC::ItemStorage.table_name} as ist WHERE "+
      "i.policy_id = p.id AND ist.item_id = i.id AND i.copies > 0 AND i.copies < p.copies AND i.status = 'ready' AND ist.status <> 'delete' GROUP BY i.id LIMIT 1000"
    r = FC::DB.connect.query(sql)
    r.each do |row|
      $log.info("GlobalDaemonThread: new item_storage for item #{row['item_id']}")
      item_storages = row['storages'].split(',')
      if row['item_copies'] != item_storages.size
        $log.warn("GlobalDaemonThread: ItemStorage count <> item.copies for item #{row['item_id']}")
      elsif item_storages.size >= row['policy_copies']
        $log.warn("GlobalDaemonThread: ItemStorage count >= policy.copies for item #{row['item_id']}")
      else
        src_storage = all_storages.detect{|s| item_storages.first == s.name}
        policy = all_policies.detect{|p| row['policy_id'] == p.id}
        storage = policy.get_proper_storage_for_copy(row['size'], src_storage.copy_id, item_storages) if src_storage && policy 
        error 'No available storage', :item_id => row['item_id'] unless storage
        FC::Item.new(:id => row['item_id']).make_item_storage(storage, 'copy')
      end
    end
  end
end