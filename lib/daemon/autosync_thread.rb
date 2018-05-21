require 'autosync'

class AutosyncThread < BaseThread
  attr_accessor :start_time, :files_to_delete, :items_to_delete
  def go(storages)
    storages.each do |storage|
      $log.debug("AutosyncThread: Run storage synchronization for #{storage.name}")
      Autosync.new(storage).run
      storage.reload
      storage.autosync_at = Time.now.to_i
      storage.save
      $log.debug("AutosyncThread: Finish storage synchronization for #{storage.name}")
      break if $exit_signal
    end
  end
end
