# encoding: utf-8

module FC
  class Error < DbBase
    set_table :errors, 'item_id, item_storage_id, host, message, time'
    
    def self.raise(error, options = {})
      self.new(options.merge(:host => FC::Storage.curr_host, :message => error)).save
      Kernel.raise error
    end 
  end
end
