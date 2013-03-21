# encoding: utf-8

module FC
  class DbBase
    attr_accessor :id
    
    def initialize(params = {})
      @@table_fields.each {|key| self.send("#{key}=", params[key] || params[key.to_sym]) }
      @id = (params["id"] || params[:id]).to_i if params["id"] || params[:id]
      @database_fields = params[:database_fields] || {}
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
      database_fields = r.first.select{|key, val| @@table_fields.include?(key.to_s)}
      self.new(database_fields.merge({:id => id, :database_fields => database_fields}))
    end
    
    # сохранить изменения в базу
    def save
      sql = @id ? "UPDATE #{@@table_name} SET " : "INSERT IGNORE INTO #{@@table_name} SET "
      fields = []
      @@table_fields.each do |key|
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
        @@table_fields.each do |key|
          @database_fields[key] = self.send(key)
        end
      end
    end

    # удалить элемент из базы
    def delete
      FC::DB.connect.query("DELETE FROM #{@@table_name} WHERE id=#{@id.to_i}") if @id
    end
  end
end
