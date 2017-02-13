class CheckThread < BaseThread
  def go(storage_name)
    $log.debug("CheckThread: Run stotage check for #{storage_name}")
    storage = $storages.detect{|s| s.name == storage_name}
    if File.writable?(storage.path)
      storage.size_limit = storage.get_real_size if storage.auto_size?
      # also saves size_limit
      storage.update_check_time
    else 
      error "Storage #{storage.name} with path #{storage.path} not writable"
    end
    $log.debug("CheckThread: Finish stotage check for #{storage_name}")
  end
end