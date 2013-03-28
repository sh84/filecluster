# encoding: utf-8

module FC
  class Error < DbBase
    set_table :errors, 'item_id, item_storage_id, host, message, time'
    
  end
end
