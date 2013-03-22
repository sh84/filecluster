# encoding: utf-8

module FC
  class Storage < DbBase
    set_table :storages, 'name, host, path, url, size, size_limit'
    
  end
end
