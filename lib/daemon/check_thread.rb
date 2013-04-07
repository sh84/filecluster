class CheckThread < BaseThread
  def go(storage_name)
    storage = $storages.detect{|s| s.name == storage_name}
    if File.writable?(storage.path)
      storage.update_check_time
    else 
      error "Storage #{storage.name} with path #{storage.path} not writable"
    end
  end
end