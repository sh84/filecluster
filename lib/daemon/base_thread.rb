class BaseThread < Thread
  def initialize(*args)
    super(*args) do |*p|
      begin
        self.go(*p)
      rescue Exception => e
        error "#{self.class}: #{e.message}; #{e.backtrace.join(', ')}"
      end
      FC::DB.close
    end
  end
end