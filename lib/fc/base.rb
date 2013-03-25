# encoding: utf-8

module FC
  class DbBase
    attr_accessor :id, :database_fields
    
    class << self
      attr_accessor :table_name, :table_fields
    end
    
    def initialize(params = {})
      self.class.table_fields.each {|key| self.send("#{key}=", params[key] || params[key.to_sym]) }
      @id = (params["id"] || params[:id]).to_i if params["id"] || params[:id]
      @database_fields = params[:database_fields] || {}
    end
    
    def self.set_table(name, fields)
      self.table_name = "#{FC::DB.prefix}#{name}"
      self.table_fields = fields.split(',').map{|e| e.gsub(' ','')}
      self.table_fields.each{|e| attr_accessor e.to_sym}
    end
    
    # получить элемент из базы
    def self.find(id)
      r = FC::DB.connect.query("SELECT * FROM #{self.table_name} WHERE id=#{id.to_i}")
      raise "Record not found (#{self.table_name}.id=#{id})" if r.count == 0
      # сохраняем только объявленные поля
      database_fields = r.first.select{|key, val| self.table_fields.include?(key.to_s)}
      self.new(database_fields.merge({:id => id, :database_fields => database_fields}))
    end
    
    # сохранить изменения в базу
    def save
      sql = @id ? "UPDATE #{self.class.table_name} SET " : "INSERT IGNORE INTO #{self.class.table_name} SET "
      fields = []
      self.class.table_fields.each do |key|
        db_val = @database_fields[key]
        val = self.send(key)
        if val.to_s != db_val.to_s || val.nil? && !db_val.nil? || !val.nil? && db_val.nil?
          fields << "#{key}=#{val ? (val.class == String ? "'#{FC::DB.connect.escape(val)}'" : val.to_i) : 'NULL'}"
        end
      end
      if fields.length > 0
        sql << fields.join(',')
        sql << " WHERE id=#{@id.to_i}" if @id
        FC::DB.connect.query(sql)
        @id = FC::DB.connect.last_id unless @id
        self.class.table_fields.each do |key|
          @database_fields[key] = self.send(key)
        end
      end
    end
    
    # перезагрузить из базы
    def reload
      raise "Can't reload object without id" if !@id || @id.to_i == 0
      new_obj = self.class.find(@id)
      self.database_fields = new_obj.database_fields
      self.class.table_fields.each {|key| self.send("#{key}=", new_obj.send(key)) }
    end

    # удалить элемент из базы
    def delete
      FC::DB.connect.query("DELETE FROM #{self.class.table_name} WHERE id=#{@id.to_i}") if @id
    end
  end
end
