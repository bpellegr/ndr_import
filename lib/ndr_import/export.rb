#require 'ndr_import/table'
#require 'ndr_import/file/registry'

module NdrImport
  # This class manages the export of data
  #
  class Export

    def all_valid_options
      # relation
      # mapping
      # header_lines
      # footer_lines
      # format
      # filename
      # columns
      %w(relation mapping header_lines footer_lines format filename columns)
    end

    # Must have a relation OR mapping (mapping defines relation ??)
    # all other params optional
    def initialize(options = {})
      options.stringify_keys! if options.is_a?(Hash)
      validate_options(options)

      all_valid_options.each do |key|
        value = options[key]
        value = true if key == :header_lines && options[key].nil?
        value = true if key == :footer_lines && options[key].nil?
        if key == 'columns' && !options[key].nil? && options[key].kind_of?(Array)
          value = options[key].collect {|a| {'column' => a, 'mappings' => [{'field' => a}]}}
        end
        options[key] && instance_variable_set("@#{key}", value)
      end
      if !@mapping.nil?
        # this is probably wrong - relation should be a join of tables - where i assumed could be 'a'
        instance_variable_set("@relation", @mapping.klass.constantize)
        instance_variable_set("@columns", @mapping.columns)
      end
    end

    def each(&block)
      enum = Enumerator.new do |y|
        extract_rows { |entity, columns| y << [entity, columns] }
      end

      block ? enum.each(&block) : enum
    end

    def column_names
      @columns.collect { |column| column['column'] }
    end

    def to_csv
      to_csv_enum.sum
    end

    # Allow downloads to be streamed back as they're generated:
    def to_csv_enum
      Enumerator.new do |enum|
        enum << CSV.generate_line(column_names)
        each { |_entity, columns| enum << CSV.generate_line(columns) }
      end
    end

    private

    def validate_options(hash)
      fail ArgumentError unless hash.is_a?(Hash)
      fail ArgumentError, "Unrecognised options: #{unrecognised_options.inspect}" if !(hash.keys - all_valid_options).empty?
      fail ArgumentError, "Must supply mapping OR relation" if (hash.keys & %w(relation mapping)).count != 1
    end

    def extract_rows
      @relation.find_each do |record|
        row_data = extract_columns(record)
        yield record, row_data
      end
    end

    # Finds a entry from @columns matching `column_name`.
    def find_column(column_name)
      @columns.find { |column| column['column'] == column_name }
    end

    # Returns the index/position of `column`.
    def column_index(column)
      @columns.find_index(column)
    end

    def extract_columns(entity)
      Array.new(@columns.count).tap do |row|
        columns_for(entity).each do |column|
          index = column_index(column)
          value = extract_column_value(entity, column)
          row[index] = value
        end
      end
    end

    # Returns a collection of columns that are attributable to `entity`.
    def columns_for(entity)
      @columns.select do |column|
        if !column['klass'].nil?
          Array.wrap(column['klass']).find do |klass|
            entity.class.name.demodulize == klass.demodulize
          end
        elsif !column['mappings'].nil?
          Array.wrap(column['mappings']).find do |mapping|
            !entity.try{mapping['field']}.nil?
          end
        end
      end
    end

    def extract_column_value(entity, column)
      field = column.dig('mappings', 0, 'field')

      try_formatting(column) do
        if field.respond_to?(:call)
          field.call(entity)
        elsif entity.respond_to?("#{field}_lookup_value") && use_lookup_values?
          entity.try("#{field}_lookup_value")
        else
          entity.try(field)
        end
      end
    end

    # NOTE: This could be cleaner if the import mapping was expecting dates in a consistent format.
    def try_formatting(column)
      value = yield
      return value unless value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime)

      pattern = @date_pattern || column.dig('mappings', 0, 'format')
      pattern ? value.strftime(pattern) : value
    end

    # Cascades data items from `right` to `left` (unless already populated in `left`).
    # This is essentially how we're pulling in data from the `parent` entity/row into the current
    # entity/row.
    def merge_row(left, right)
      left.fill { |i| left[i] || right[i] }
    end

  end

end
