# encoding: utf-8
require 'shellwords'
require 'fileutils'
module FC
  class Item < DbBase
    set_table :items, 'name, tag, outer_id, policy_id, dir, size, md5, status, time, copies'

    # Create item by local path.
    # Additional options:
    #   :replace=true - replace item if it exists
    #   :remove_local=true - delete local_path file/dir after add
    #   :additional_fields - hash of additional FC:Item fields
    #   :no_md5 - don't use md5
    #   :speed_limit - limit copy speed
    # If item_name is part of local_path it processed as inplace - local_path is valid path to the item for policy
    def self.create_from_local(local_path, item_name, policy, options={}, &block)
      raise 'Path not exists' unless File.exists?(local_path)
      raise 'Policy is not FC::Policy' unless policy.instance_of?(FC::Policy)
      item_params = options.merge({
        :name => item_name.to_s.gsub('//', '/').sub(/\/$/, '').sub(/^\//, '').strip,
        :policy_id => policy.id,
        :dir => File.directory?(local_path),
        :size => FC::Storage.new(:host => FC::Storage.curr_host).file_size(local_path),
        :md5 => nil
      })
      item_params[:md5] = FC::Storage.new(
        :host => FC::Storage.curr_host
      ).md5_sum(local_path) unless item_params[:no_md5]
      item_params.delete(:replace)
      item_params.delete(:remove_local)
      item_params.delete(:not_local)
      item_params.delete(:no_md5)
      item_params.delete(:speed_limit)
      raise 'Name is empty' if item_params[:name].empty?
      raise 'Zero size path' if item_params[:size] == 0


      if local_path.include?(item_name) && !options[:not_local]
        storage = policy.get_create_storages.detect do |s|
          s.host == FC::Storage.curr_host && local_path.index(s.path) == 0 && local_path.sub(s.path, '').sub(/\/$/, '').sub(/^\//, '') == item_params[:name]
        end
        
        FC::Error.raise "local_path #{local_path} is not valid path for policy ##{policy.id}" unless storage
      end

      # new item?
      item = FC::Item.where('name=? AND policy_id=?', item_params[:name], policy.id).first
      if item
        if options[:replace] || storage
          # replace all fields
          item_params.each{|key, val| item.send("#{key}=", val)}
        else
          FC::Error.raise 'Item already exists', :item_id => item.id
        end
      else
        item = FC::Item.new(item_params)
      end
      item.save

      if storage
        item_storage = item.make_item_storage(storage, 'ready')
        item.reload
      else
        if item.copies.to_i > 0
          # find storage in item.item_storages
          storages_names = item.get_item_storages.select{|s| s.status == 'ready'}.map(&:storage_name)
          storage = FC::Storage.select_proper_storage_for_create(policy.get_create_storages, item.size) do |storages|
            storages.select{|s| storages_names.detect(s.name)}
          end
        end
        if block_given?
          storage ||= FC::Storage.select_proper_storage_for_create(policy.get_create_storages,
                                                                   item.size, &block)
        else
          storage ||= policy.get_proper_storage_for_create(item.size, local_path)
        end
        FC::Error.raise 'No available storage', :item_id => item.id unless storage

        # mark delete item_storages on replace
        FC::DB.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{item.id} AND storage_name <> '#{storage.name}'") if options[:replace]

        item_storage = item.make_item_storage(storage)
        item.copy_item_storage(local_path, storage, item_storage, options[:remove_local], options[:speed_limit])
      end

      return item
    end

    def make_item_storage(storage, status = 'new')
      # new storage_item?
      item_storage = FC::ItemStorage.where('item_id=? AND storage_name=?', id, storage.name).first
      if item_storage
        item_storage.delete
        storage.size = storage.size.to_i - size.to_i
      end

      item_storage = FC::ItemStorage.new({:item_id => id, :storage_name => storage.name, :status => status})
      item_storage.save
      storage.size = storage.size.to_i + size.to_i
      item_storage
    end

    def copy_item_storage(src, storage, item_storage, remove_local = false, speed_limit = nil)
      begin
        if src.instance_of?(FC::Storage)
          src.copy_to_local(name, "#{storage.path}#{name}", speed_limit)
        else
          storage.copy_path(src, name, remove_local, speed_limit)
        end
        md5_on_storage = storage.md5_sum(name) if md5
      rescue Exception => e
        item_storage_status_set(item_storage, 'error')
        FC::Error.raise "Copy error: #{e.message}", :item_id => id, :item_storage_id => item_storage.id
      else
        begin
          item_storage.reload
        rescue Exception => e
          FC::Error.raise "After copy error: #{e.message}", :item_id => id, :item_storage_id => item_storage.id
        else
          if md5 && md5_on_storage != md5
            item_storage_status_set(item_storage, 'error')
            FC::Error.raise "Check md5 after copy error", :item_id => id, :item_storage_id => item_storage.id
          else
            item_storage_status_set(item_storage, 'ready')
            if remove_local && !src.instance_of?(FC::Storage) && File.exists?(src)
              if File.directory?(src)
                FileUtils.rm_r(src)
              else
                File.delete(src)
              end
            end
          end
        end
      end
    end

    def item_storage_status_set(item_storage, status)
      reload
      marked_for_delete = self.status == 'deferred_delete'
      item_storage.status = status
      item_storage.save
      reload
      mark_deleted if marked_for_delete
    end

    # mark item and his items_storages for deferred delete
    # real delete after policy.delete_deferred_time
    def mark_deleted
      self.status = 'deferred_delete'
      save
    end

    # mark item and his items_storages for immediate delete
    def immediate_delete
      FC::DB.query("UPDATE #{FC::ItemStorage.table_name} SET status='delete' WHERE item_id = #{id}")
      self.status = 'delete'
      save
    end

    def dir?
      dir.to_i == 1
    end

    def get_item_storages
      FC::ItemStorage.where("item_id = #{id}")
    end

    def get_available_storages
      r = FC::DB.query("SELECT st.* FROM #{FC::Storage.table_name} as st, #{FC::ItemStorage.table_name} as ist WHERE
        ist.item_id = #{id} AND ist.status='ready' AND ist.storage_name = st.name")
      r.map{|data| FC::Storage.create_from_fiels(data)}.select {|storage| storage.up? && storage.url_weight.to_i >= 0}
    end

    def urls
      get_available_storages.map{|storage| File.join(storage.url, name)}
    end

    def url
      available_storages = get_available_storages()
      # sort by random(url_weight)
      best_storage = available_storages.map{ |storage|
        [storage, Kernel.rand(storage.url_weight.to_i * 100)]
      }.sort{ |a, b|
        a[1] <=> b[1]
      }.map{|el| el[0]}.last
      best_storage = available_storages.sample unless best_storage
      raise "URL find - no avable storage for item #{id}" unless best_storage
      File.join(best_storage.url, name)
    end
  end
end
