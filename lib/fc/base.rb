# encoding: utf-8

module FC
  class DbBase
    attr_accessor :id
    
    def initialize(params = {})
      params.each{|key, val| self.send("#{key}=", val)}
      @id = @id.to_i if @id
      @database_fields = {} unless @database_fields
    end
    
    def self.set_table(name, fields)
      @@table_name = "#{FC::DB.prefix}#{name}"
      @@table_fields = fields.split(',').map{|e| e.gsub(' ','')}
      @@table_fields.each{|e| attr_accessor e.to_sym}
    end
    
    # получить элемент из базы
    def self.load(id)
      r = FC::DB.connect.query("SELECT * FROM #{@@table_name} WHERE id=#{id.to_i}")
      raise "Record not found (#{@@table_name}.id=#{id})" if r.count == 0
      # сохраняем только объявленные поля
      self.new(@database_fields = r.first.select{|key, val| key == "id" || @@table_fields[key]})
    end
    
    # сохранить изменения в базу
    def save
      sql = @id ? "UPDATE #{@@table_name} SET " : "INSERT IGNORE INTO #{@@table_name} SET "
      fields = []
      @@table_fields.each do |key|
        val = @database_fields[key]
        if self.send(key).to_s != val.to_s || self.send(key).nil? && !val.nil? || !self.send(key).nil? && val.nil?
          fields << "#{key}=#{val ? (nil.class == String ? connect.escape(val) : val) : 'NULL'} "
        end
      end
      if fields.length > 0
        sql << fields.join(',')
        sql << "WHERE id=#{@id.to_i}" if @id
        FC::DB.connect.query(sql)
        @id = FC::DB.connect.last_id unless @id
        @@table_fields.each do |key|
          @database_fields[key] = self.send(key)
        end
      end
    end

    # удалить элемент из базы
    def delete
      FC::DB.connect.query("DELETE FROM #{@@table_name} WHERE id=#{@id.to_i}")
    end
  end
end
