class GlobalDaemonThread < BaseThread
  def go(timeout)
    $log.info("Start global daemon thread with timeout=#{timeout}")
    while true do
      exit if $exit_signal
      sleep timeout.to_f/2
      exit if $exit_signal
      
      if FC::Var.get('global_daemon_host') == FC::Storage.curr_host
        FC::Var.set('global_daemon_host', FC::Storage.curr_host)
      else
        $log.info("Exit from GlobalDaemonThread: global daemon already running on #{FC::Var.get('global_daemon_host')}")
        FC::DB.close
        exit
      end
      
      make_item_copies
      make_deleted_error_items_storages
      make_deleted_error_items
      delete_deleted_items
      #TODO: периодически удалять (проставлять статус delete) для лиших is (число копий больше необходимого)
    end
  end
  
  # make item copies by policy
  def make_item_copies
    $log.debug("GlobalDaemonThread: make_item_copies")
    
    all_storages = FC::Storage.where
    all_policies = FC::Policy.where
    
    limit = FC::Var.get('daemon_global_tasks_group_limit', 1000).to_i
    all_policies.each do |policy|
      next if policy.copies.to_i < 2
      copies = (1..policy.copies.to_i-1).to_a.join(',')
      sql = "SELECT i.id as item_id, i.size, i.copies as item_copies, i.name, i.tag, i.dir, GROUP_CONCAT(ist.storage_name ORDER BY ist.id) as storages "+
        "FROM #{FC::Item.table_name} as i, #{FC::ItemStorage.table_name} as ist WHERE i.policy_id = #{policy.id} AND "+
        "ist.item_id = i.id AND i.copies IN (#{copies}) AND i.status = 'ready' AND ist.status <> 'delete' GROUP BY i.id LIMIT #{limit}"
      r = FC::DB.query(sql)
      r.each do |row|
        $log.info("GlobalDaemonThread: new item_storage for item #{row['item_id']}")
        item_storages = row['storages'].split(',')
        if row['item_copies'] != item_storages.count
          $log.warn("GlobalDaemonThread: ItemStorage count <> item.copies for item #{row['item_id']}")
        elsif item_storages.count >= policy.copies.to_i
          $log.warn("GlobalDaemonThread: ItemStorage count >= policy.copies for item #{row['item_id']}")
        else
          src_storage = all_storages.detect{|s| item_storages.first == s.name}
          if src_storage
            storage = FC::CopyRule.get_proper_storage_for_copy(
              :item_id     => row['item_id'],
              :size        => row['size'],
              :item_copies => row['item_copies'],
              :name        => row['name'],
              :tag         => row['tag'],
              :dir         => row['dir'].to_i == 1,
              :src_storage => src_storage,
              :exclude     => item_storages
            )
            storage = src_storage.get_proper_storage_for_copy(row['size'], item_storages) unless storage
          end
          if storage
            FC::Item.new(:id => row['item_id'], :size => row['size']).make_item_storage(storage, 'copy')
          else
            error 'No available storage', :item_id => row['item_id']
          end
        end
      end
    end
  end
  
  def delete_deleted_items
    $log.debug("GlobalDaemonThread: delete_deleted_items")
    
    r = FC::DB.query("SELECT i.id FROM #{FC::Item.table_name} as i LEFT JOIN #{FC::ItemStorage.table_name} as ist ON i.id=ist.item_id WHERE i.status = 'delete' AND ist.id IS NULL")
    ids = r.map{|row| row['id']}
    if ids.count > 0
      ids = ids.join(',')
      FC::DB.query("DELETE FROM #{FC::Item.table_name} WHERE id in (#{ids})")
      $log.info("GlobalDaemonThread: delete items #{ids}")
    end
  end
  
  def make_deleted_error_items_storages
    $log.debug("GlobalDaemonThread: make_deleted_error_items_storages")
    ttl = FC::Var.get('daemon_global_error_items_storages_ttl', 86400).to_i
    cnt = FC::DB.query("SELECT count(*) as cnt FROM #{FC::ItemStorage.table_name} WHERE status IN ('error', 'copy') AND time < #{Time.new.to_i - ttl}").first['cnt']
    $log.debug("GlobalDaemonThread: mark deleted #{cnt} items storages")
    FC::DB.query("UPDATE #{FC::ItemStorage.table_name} SET status = 'delete' WHERE status IN ('error', 'copy') AND time < #{Time.new.to_i - ttl}")
  end
  
  def make_deleted_error_items
    $log.debug("GlobalDaemonThread: make_deleted_error_items")
    ttl = FC::Var.get('daemon_global_error_items_ttl', 86400).to_i
    cnt = FC::DB.query("SELECT count(*) as cnt FROM #{FC::Item.table_name} WHERE status = 'error' AND time < #{Time.new.to_i - ttl}").first['cnt']
    $log.debug("GlobalDaemonThread: mark deleted #{cnt} items")
    FC::DB.query("UPDATE #{FC::Item.table_name} SET status = 'delete' WHERE status = 'error' AND time < #{Time.new.to_i - ttl}")
  end
end