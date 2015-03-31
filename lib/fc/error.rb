# encoding: utf-8

module FC
  class Error < DbBase
    set_table :errors, 'item_id, item_storage_id, host, message, time'
    
    def self.raise(error, options = {})
      if error.kind_of?(Exception)
        err = FC::Exception.new(error.message)
        err.set_backtrace(error.backtrace)
      else
        err = FC::Exception.new(error)
        err.set_backtrace(caller)
      end
      self.new(options.merge(:host => FC::Storage.curr_host, :message => err.message)).save
      Kernel.raise err unless options[:not_raise]
    end 
  end
  
  class Exception < StandardError
  end
end

