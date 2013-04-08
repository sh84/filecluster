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
    sql = "SELECT items.* FROM items, policies WHERE items.policy_id = policies.id AND items.copies > 0 AND items.copies < policies.copies AND items.status = 'ready' LIMIT 1000"
    items = FC::DB.connect.query(sql).map{|data| FC::Item.create_from_fiels(data)}
    items.each do |item|
      $log.info("GlobalDaemonThread: new item_storage for item #{item.id}")
      policy = FC::Policy.find(item.policy_id) rescue nil
      item_storages = FC::ItemStorage.where("item_id=? AND status <> 'delete'", item.id)
      
      if !policy
        error 'No policy for item', :item_id => item.id
      elsif item.copies != item_storages.size
        $log.warn("GlobalDaemonThread: ItemStorage count <> item.copies for item #{item.id}")
      elsif item_storages.size >= policy.copies
        $log.warn("GlobalDaemonThread: ItemStorage count >= policy.copies for item #{item.id}")
      else
        storage = policy.get_proper_storage(item.size, item_storages.map(&:storage_name))
        error 'No available storage', :item_id => item.id unless storage
        item.make_item_storage(storage, 'copy')
      end
    end
  end
end