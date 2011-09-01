module Vertica
  class Result
    
    include Enumerable
    
    attr_reader :columns
    attr_reader :rows

    def initialize
      @rows = []
    end

    def descriptions=(message)
      @columns = message.fields.map { |fd| Column.new(fd) }
    end

    def format_row(row_data)
      row = {}
      row_data.fields.each_with_index do |field, idx|
        col = columns[idx]
        row[col.name] = col.convert(field)
      end
      row
    end

    def add_row(row_data)
      @rows << format_row(row_data)
    end

    def each_row(&block)
      @rows.each(&block)
    end
    
    alias_method :each, :each_row

    def row_count
      @rows.size
    end

    alias_method :size, :row_count
    alias_method :length, :row_count
  end
end
