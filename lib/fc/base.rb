# encoding: utf-8

module FC
  class DbBase
    attr_accessor :id, :database_fields
    
    class << self
      attr_accessor :table_name, :table_fields, :validates, :before_saves, :after_saves
    end
    
    def initialize(params = {})
      self.class.table_fields.each {|key| self.send("#{key}=", params[key] || params[key.to_sym]) }
      @id = (params["id"] || params[:id]).to_i if params["id"] || params[:id]
      @database_fields = params[:database_fields] || {}
    end
    
    def self.table_name
      FC::DB.connect unless FC::DB.options
      "#{FC::DB.prefix}#{@table_name}"
    end
        
    # define table name and fieldsp
    def self.set_table(name, fields)
      @table_name = name
      self.table_fields = fields.split(',').map{|e| e.gsub(' ','')}
      self.table_fields.each{|e| attr_accessor e.to_sym}
    end
    
    # make instance on fields hash
    def self.create_from_fiels(data)
      # use only defined in set_table fields
      database_fields = data.select{|key, val| self.table_fields.include?(key.to_s)}
      self.new(database_fields.merge({:id => data["id"].to_s, :database_fields => database_fields}))
    end
    
    # get element by id
    def self.find(id)
      r = FC::DB.query("SELECT * FROM #{self.table_name} WHERE id=#{id.to_i}")
      raise "Record not found (#{self.table_name}.id=#{id})" if r.count == 0
      self.create_from_fiels(r.first)
    end
    
    # get elements array by sql condition (possibles '?' placeholders)
    def self.where(cond = "1", *params)
      i = -1
      sql = "SELECT * FROM #{self.table_name} WHERE #{cond.gsub('?'){i+=1; "'#{Mysql2::Client.escape(params[i].to_s)}'"}}"
      r = FC::DB.query(sql)
      r.map{|data| self.create_from_fiels(data)}
    end

    # get elements count by sql condition (possibles '?' placeholders)
    def self.count(cond = "1", *params)
      i = -1
      sql = "SELECT count(*) as cnt FROM #{self.table_name} WHERE #{cond.gsub('?'){i+=1; "'#{Mysql2::Client.escape(params[i].to_s)}'"}}"
      FC::DB.query(sql).first['cnt']
    end
    
    # get all elements array
    def self.all
      self.where
    end
    
    # save all fields without validates & savers
    def save
      sql = @id.to_i != 0 ? "UPDATE #{self.class.table_name} SET " : "INSERT IGNORE INTO #{self.class.table_name} SET "
      fields = []
      self.class.table_fields.each do |key|
        val = self.send(key)
        val = 1 if val == true
        val = 0 if val == false
        fields << "#{key}=#{val ? (val.class == String ? "'#{FC::DB.connect.escape(val)}'" : val.to_i) : 'NULL'}"
      end
      if fields.length > 0
        sql << fields.join(',')
        sql << " WHERE id=#{@id.to_i}" if @id
        FC::DB.query(sql)
        @id = FC::DB.connect.last_id unless @id
        self.class.table_fields.each do |key|
          @database_fields[key] = self.send(key)
        end
      end
    end
    
    # save changed fields
    def save
      self.validate!
      sql = @id.to_i != 0 ? "UPDATE #{self.class.table_name} SET " : "INSERT IGNORE INTO #{self.class.table_name} SET "
      fields = []
      self.class.table_fields.each do |key|
        db_val = @database_fields[key]
        val = self.send(key)
        val = 1 if val == true
        val = 0 if val == false
        if val.to_s != db_val.to_s || val.nil? && !db_val.nil? || !val.nil? && db_val.nil?
          fields << "#{key}=#{val ? (val.class == String ? "'#{FC::DB.connect.escape(val)}'" : val.to_i) : 'NULL'}"
        end
      end
      if fields.length > 0
        call_saves(self.class.before_saves)
        sql << fields.join(',')
        sql << " WHERE id=#{@id.to_i}" if @id
        FC::DB.query(sql)
        @id = FC::DB.connect.last_id unless @id
        call_saves(self.class.after_saves)
        self.class.table_fields.each do |key|
          @database_fields[key] = self.send(key)
        end
      end
    end
    
    # reload object from DB
    def reload
      raise "Can't reload object without id" if !@id || @id.to_i == 0
      new_obj = self.class.find(@id)
      self.database_fields = new_obj.database_fields
      self.class.table_fields.each {|key| self.send("#{key}=", new_obj.send(key)) }
    end
    
    # delete object from DB without savers
    def delete!
      FC::DB.query("DELETE FROM #{self.class.table_name} WHERE id=#{@id.to_i}") if @id
    end

    # delete object from DB
    def delete
      call_saves(self.class.before_saves, true)
      FC::DB.query("DELETE FROM #{self.class.table_name} WHERE id=#{@id.to_i}") if @id
      call_saves(self.class.after_saves, true)
    end
    
    # class method - dsl
    def self.validate(field, params={})
      puts "validate #{field}"
      raise "validate without :as" unless params[:as]
      @validates = [] unless @validates
      @validates << params.merge(:field => field)
      # all validates save to FC::DbBase
      if self.superclass == FC::DbBase
        FC::DbBase.validates = {} unless FC::DbBase.validates
        FC::DbBase.validates[params[:as].to_sym] = [] unless FC::DbBase.validates[params[:as].to_sym]
        FC::DbBase.validates[params[:as].to_sym] << params.merge(:field => field, :klass => self)
      end
    end
    
    # called on save and delete, or manually
    def validate!
      if self.class.validates 
        self.class.validates.each do |v|
          val = self.send(v[:field])
          new_val = val
          if v[:as] == :storages
            storages ||= FC::Storage.all.map(&:name)
            new_val = val.gsub(/^\s*|\s*$/, '').split(/\s*\,\s*/).delete_if do |s|
              !storages.include?(s)
            end.join(',')
          end
          self.send("#{v[:field]}=", new_val) if new_val != val
        end
      end
    end
    
    def self.before_save(field = nil, &block)
      @before_saves = [] unless @before_saves
      @before_saves << [field, block] if block
    end    
    
    def self.after_save(field = nil, &block)
      @after_saves = [] unless @after_saves
      @after_saves << [field, block] if block
    end
    
    private
    
    def call_saves(list, is_delete = false)
      if list
        list.each do |s|
          field, block = s
          if field
            old_val = @database_fields[field.to_s]
            val = self.send(field.to_s)
            block.call(old_val, is_delete) if old_val && old_val != val
          else
            block.call(nil, is_delete)
          end
        end
      end
    end
    
  end
end
