class GlobalDaemonThread < BaseThread
  def go(timeout)
    $log.info("Start global daemon thread")
    while true do
      exit if $exit_signal
      sleep timeout/2
      exit if $exit_signal
      
      r = FC::DB.connect.query("SELECT #{FC::DB.prefix}vars.*, UNIX_TIMESTAMP() as curr_time FROM #{FC::DB.prefix}vars WHERE name='global_daemon_host'").first
      if r['val'] == FC::Storage.curr_host
        FC::DB.connect.query("UPDATE #{FC::DB.prefix}vars SET val='#{FC::Storage.curr_host}' WHERE name='global_daemon_host'")
      else
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
    sql = "SELECT items.* FROM items, policies WHERE items.policy_id = policies.id AND items.copies > 0 AND items.copies < policies.copies AND items.status = 'ready' LIMIT 1000"
    items = FC::DB.connect.query(sql).map{|data| FC::Item.create_from_fiels(data)}
    items.each do |item|
      policy = FC::Policy.find(item.policy_id) rescue nil
      storage = policy.get_proper_storage(item.size) if policy
      error 'No available storage', :item_id => item.id unless storage
      item.make_item_storage(storage, 'copy')
    end
  end
end