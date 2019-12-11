class CheckThread < BaseThread
  require "net/http"
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
    check_http(storage)
    $log.debug("CheckThread: Finish stotage check for #{storage_name}")
  end

  def check_http(storage)
    url = "#{storage.url}healthcheck"
    uri = URI.parse(url.sub(%r{^\/\/}, 'http://'))
    request = Net::HTTP.new(uri.host, uri.port)
    request.read_timeout = request.open_timeout = 2
    resp = request.start { |http| http.get(uri.path) } rescue nil
    if resp && resp.code.to_i == 200 && resp.body.to_s.chomp == 'OK'
      storage.update_http_check_time
    else
      error "Storage #{storage.name} with url #{storage.url} not readable"
    end
  rescue => err
    $log.error("CheckThread: check_http error: #{err}")
  end
end
