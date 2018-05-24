require 'iostat'

class Autosync
  attr_accessor :files_to_delete, :items_to_delete
  def initialize(storage, dry_run = false)
    @dry_run = dry_run
    @start_time = Time.now.to_i - 3600
    @storage = storage
    @files_to_delete = []
    @items_to_delete = []
    @removed_files_size = 0
    @io_stat = Iostat.new(@storage.path)
  end

  def self.error(msg, options = {})
    $log.error(msg) if $log
    FC::Error.new(options.merge(:host => FC::Storage.curr_host, :message => msg)).save
  end

  def run
    @db_struct = fill_db
    $log.debug("Autosync: Scanning disk #{@storage.name} (#{@storage.path})") if $log
    scan_disk(@db_struct, '')
    return if $exit_signal
    $log.debug("Autosync: Scanning DB items #{@storage.name}") if $log
    scan_db(@db_struct, '')
    return if $exit_signal
    delete_diffs unless @dry_run
  ensure
    @io_stat.stop
  end

  def relax_drive
    sleep 1 while @io_stat.util > 50
  end

  def fill_db
    $log.debug("Autosync: Reading DB items for #{@storage.name} ...") if $log

    db_struct = {}
    last_item_storage_id = 0
    items_count = 0
    loop do
      items = FC::DB.connect.query(%(
        SELECT its.id, itm.name
        FROM #{FC::Item.table_name} itm
        JOIN #{FC::ItemStorage.table_name} its ON its.item_id = itm.id
        WHERE its.storage_name = '#{@storage.name}'
        AND its.status = 'ready'
        AND its.id > #{last_item_storage_id}
        ORDER BY its.id
        LIMIT 10000
      ), cache_rows: false, symbolize_keys: true).to_a
      break if $exit_signal

      # make tree structure with array of values (items) on leafs
      items.each do |i|
        items_count += 1
        last_item_storage_id = i[:id]
        ref = db_struct
        path = i[:name].split('/')
        last_idx = path.size - 1
        path.each_with_index do |part, idx|
          if idx == last_idx
            ref[part] = [false, i[:id]]
          else
            ref[part] ||= {}
            ref = ref[part]
          end
        end
      end
      break unless items.size == 10_000
    end
    $log.debug("Autosync: Reading DB items for #{@storage.name} done. Items: #{items_count}") if $log
    db_struct
  end

  def scan_disk(db_path, relative_path)
    return if $exit_signal
    sleep 0.001
    relax_drive
    Dir.glob("#{@storage.path}#{relative_path}*").each do |disk_entry|
      next if disk_entry == "#{@storage.path}healthcheck"
      db_item = db_path[disk_entry.split('/').last]
      case
      when db_item.is_a?(Array) # tree leaf
        db_item[0] = true # mark db_item as exists on disk
      when db_item.is_a?(Hash) && File.directory?(disk_entry) # tree node
        scan_disk(db_item, "#{disk_entry[@storage.path.size..-1]}/")
      else # not found in db
        mtime = File.stat(disk_entry).mtime.to_i rescue Time.now.to_i
        @files_to_delete << disk_entry if @start_time > mtime # older than 1 hour
      end
    end
  end

  def scan_db(db_item, node_path)
    return if $exit_signal
    db_item.each do |item_name, item_data|
      if item_data.is_a?(Array) # tree leaf
        @items_to_delete << item_data[1] unless item_data[0]
      else # tree node
        scan_db(item_data, "#{node_path}#{item_name}/")
      end
    end
  end

  def delete_disk_entry(entry)
    return false if $exit_signal
    return true unless File.exist?(entry)
    remove = true
    stat = File.stat(entry) rescue nil
    if File.directory?(entry)
      Dir.glob("#{entry}/*").each do |sub_entry|
        relax_drive
        remove = false unless delete_disk_entry(sub_entry)
      end
    else
      mtime = stat ? stat.mtime.to_i : Time.now.to_i
      remove = @start_time > mtime
    end
    if remove
      @removed_files_size += stat.size if stat
      $log.debug("deleting disk entry #{entry}") if $log
      FileUtils.rm_rf(entry)
    end
    remove
  end

  def delete_diffs
    $log.debug("Removing #{@files_to_delete.size} disk entries") if $log
    @files_to_delete.each do |f|
      break if $exit_signal
      delete_disk_entry(f)
    end
    return if $exit_signal
    self.class.error("Autosync removed #{@files_to_delete.size} files/dirs from #{@storage.name}. Size: #{@removed_files_size} bytes") if @removed_files_size > 0
    $log.debug("Removing items #{@items_to_delete.size} from DB for #{@storage.name}") if $log
    counter = 0
    @items_to_delete.each do |item_storage_id|
      its = FC::ItemStorage.where('id = ?', item_storage_id).first
      next unless its
      its.status = 'error'
      its.save
      self.class.error("item does not exist on storage #{@storage.name}", item_storage_id: item_storage_id.to_i) rescue nil
      sleep 10 if (counter += 1) % 1000 == 0
    end
  end
end
