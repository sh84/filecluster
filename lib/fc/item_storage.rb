# encoding: utf-8

module FC
  class ItemStorage < DbBase
    set_table :items_storages, 'item_id, storage_name, status, time'
  end
end
