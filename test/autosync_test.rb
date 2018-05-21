require 'helper'
require 'autosync'

class AutosyncTest < Test::Unit::TestCase
  class << self
    def startup
      @@storage = FC::Storage.new(
        name: 'rec1-sda',
        host: 'rec1',
        size: 0,
        copy_storages: '',
        size_limit: 10,
        path: '/tmp/rec-1-sda/mediaroot/'
      )
      `mkdir -p #{@@storage.path}`
      `touch #{@@storage.path}healthcheck`
      `touch -t 9901010000 #{@@storage.path}healthcheck`
      @@storage.save
    end

    def shutdown
      FC::DB.query("DELETE FROM policies")
      FC::DB.query("DELETE FROM items_storages")
      FC::DB.query("DELETE FROM items")
      FC::DB.query("DELETE FROM storages")
      FC::DB.query("DELETE FROM errors")
      `rm -rf #{@@storage.path}` if @@storage.path
    end
  end

  def setup
    @item_storages = {}
    [
      'live_hls/otr_1/01/a.ts',
      'live_hls/otr_1/01/b.ts',
      'live_hls/otr_1/02/c.ts'
    ].each { |i| @item_storages[i] = create_item_storage(i) }
  end

  def teardown
    FC::DB.query("DELETE FROM items_storages")
    FC::DB.query("DELETE FROM items")
    FC::DB.query("DELETE FROM errors")
    `rm -rf #{@@storage.path}` if @@storage.path
  end

  should "fill_db with items on storage" do
    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    assert db_struct['live_hls']
    assert db_struct['live_hls']['otr_1']
    assert db_struct['live_hls']['otr_1']['01']
    assert db_struct['live_hls']['otr_1']['01']['a.ts']
    assert db_struct['live_hls']['otr_1']['01']['b.ts']
    assert db_struct['live_hls']['otr_1']['02']
    assert db_struct['live_hls']['otr_1']['02']['c.ts']
  end

  should "content synchonized, nothing to delete from DISK and DB" do
    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.empty?
    as.scan_db(db_struct, '')
    assert as.items_to_delete.empty?
  end

  should 'select to remove disk file entry unless found in DB' do
    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    unstored_file = "#{@@storage.path}live_hls/otr_1/01/z.ts"
    `touch -t 9901010000 #{unstored_file}`
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.size == 1
    assert as.files_to_delete.first == unstored_file
  end

  should 'physically remove disk entries older than 1 hour unless found in DB' do
    `mkdir -p #{@@storage.path}live_hls/empty_subfolders/sub1/sub2`
    `touch -t 9901010000 #{@@storage.path}live_hls/empty_subfolders`
    `touch -t 9901010000 #{@@storage.path}live_hls/empty_subfolders/sub1`
    `touch -t 9901010000 #{@@storage.path}live_hls/empty_subfolders/sub1/sub2`
    assert File.exist?("#{@@storage.path}live_hls/empty_subfolders")

    `mkdir -p #{@@storage.path}live_hls/not_empty_subfolders/sub1/sub2`
    `touch -t 9901010000 #{@@storage.path}live_hls/not_empty_subfolders`
    `touch -t 9901010000 #{@@storage.path}live_hls/not_empty_subfolders/sub1`
    assert File.exist?("#{@@storage.path}live_hls/not_empty_subfolders/sub1/sub2")

    `touch -t 9901010000 #{@@storage.path}live_hls/not_empty_subfolders/sub1/sub2/some_file`
    assert File.exist?("#{@@storage.path}live_hls/not_empty_subfolders/sub1/sub2/some_file")
    `touch -t 9901010000 #{@@storage.path}live_hls/not_empty_subfolders/sub1/sub2`

    `mkdir -p #{@@storage.path}live_hls/new_empty_folders/sub1/sub2`

    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.size == 2
    as.delete_diffs
    assert !File.exist?("#{@@storage.path}live_hls/empty_subfolders")
    assert !File.exist?("#{@@storage.path}live_hls/not_empty_subfolders")
    assert File.exist?("#{@@storage.path}live_hls/new_empty_folders/sub1/sub2")
  end

  should 'not remove folder from disk if some file appeared between disk scan and delete process' do
    # make old empty folder
    `mkdir -p #{@@storage.path}live_hls/empty_subfolders/sub1/sub2`
    `touch -t 9901010000 #{@@storage.path}live_hls/empty_subfolders`
    `touch -t 9901010000 #{@@storage.path}live_hls/empty_subfolders/sub1`
    `touch -t 9901010000 #{@@storage.path}live_hls/empty_subfolders/sub1/sub2`
    assert File.exist?("#{@@storage.path}live_hls/empty_subfolders")

    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    # scan disk
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.size == 1
    assert as.files_to_delete[0] == "#{@@storage.path}live_hls/empty_subfolders"
    # new file
    `touch #{@@storage.path}live_hls/empty_subfolders/sub1/sub2/new_appeared_file`
    as.delete_diffs
    assert File.exist?("#{@@storage.path}live_hls/empty_subfolders/sub1/sub2/new_appeared_file")
  end

  should 'select for delete file with mtime less than 1 hour' do
    old_file = "#{@@storage.path}live_hls/otr_1/01/old.ts"
    new_file = "#{@@storage.path}live_hls/otr_1/01/new.ts"
    `touch -t #{(Time.now - 3601).strftime('%Y%m%d%H%M.%S')} #{old_file}`
    `touch -t #{(Time.now - 3509).strftime('%Y%m%d%H%M.%S')} #{new_file}`
    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.size == 1
    assert as.files_to_delete.first == old_file
  end

  should 'not select for delete disk folder with entries which is in db' do
    `mkdir -p #{@@storage.path}track/01`
    create_item_storage('track/01')
    # make it all old
    `touch -t 9901010000 #{@@storage.path}track`
    `touch -t 9901010000 #{@@storage.path}track/01`
    # make some old files
    `touch -t 9901010000 #{@@storage.path}track/01/s-0001.ts`
    `touch -t 9901010000 #{@@storage.path}track/01/s-0002.ts`
    `touch -t 9901010000 #{@@storage.path}track/01/s-0003.ts`
    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.size.zero?
  end

  should 'select and remove DB item if not exist on disk' do
    item_name = @item_storages.keys.first
    `rm -f #{@@storage.path}#{item_name}`
    removed_item_storage_id = @item_storages[item_name].id
    as = Autosync.new(@@storage)
    db_struct = as.fill_db
    as.scan_disk(db_struct, '')
    assert as.files_to_delete.empty?
    as.scan_db(db_struct, '')
    assert as.items_to_delete.size == 1
    assert as.items_to_delete[0] == removed_item_storage_id
    as.delete_diffs
    @item_storages[item_name].reload
    assert @item_storages[item_name].status == 'error'
    assert FC::Error.where('1').to_a.size == 1
  end

  def create_item_storage(item_name)
    item = FC::Item.new
    item.name = item_name
    item.size = 0
    item.save
    item_storage = FC::ItemStorage.new
    item_storage.item_id = item.id
    item_storage.storage_name = @@storage.name
    item_storage.status = 'ready'
    item_storage.save
    `mkdir -p #{@@storage.path}#{File.dirname(item_name)}`
    `touch -t 9901010000 #{@@storage.path}#{item_name}`
    item_storage
  end

end
