class Wedge
  module Plugins
    module Render
      def display_errors options = {}, &block
        dom = options.delete(:dom) || _dom
        d_errors = errors

        if override_errors = options[:override_errors]
          d_errors = override_errors
        end

        keys = options.delete(:keys) || (_options[:key] ? [_options[:key]] : [])

        if extra_errors = options.delete(:errors)
          extra_errors.each do |key, value|
            d_errors[key] = value
          end
        end

        d_errors.each do |key, error|
          d_keys = (keys.dup << key)

          error = error.first

          if error.is_a?(Hash)
            d_options = options.dup
            d_options[:keys] = d_keys
            d_options[:override_errors] = d_errors[key].first

            display_errors d_options, &block
          elsif !block_given? || block.call(d_keys, error) == false
            name = d_keys.each_with_index.map do |field, i|
              i != 0 ? "[#{field}]" : field
            end.join

            if tmpl = options[:tmpl]
              if client?
                field_error_dom = DOM.new(`#{tmpl.dom}[0].outerHTML`)
              else
                field_error_dom = DOM.new(tmpl.dom.to_html)
              end
            else
              field_error_dom = DOM.new('<span class="field-error"><span>')
            end

            field_error_dom.html _error_name(key, error)

            field = dom.find("[name='#{name}']")
            field.before field_error_dom.dom
          end
        end
      end
      alias_method :render_errors, :display_errors

      def render_values dom = false, key = false, data = false
        dom = _options[:dom] unless dom
        key = _options[:key] if !key && _options.key?(:key)

        dom.find('input, select, textarea') do |element|
          name  = element['name']
          next if name.nil?
          name  = name.gsub(/\A#{key}/, '') if key
          keys  = name.gsub(/\A\[/, '').gsub(/[^a-z0-9_]/, '|').gsub(/\|\|/, '|').gsub(/\|$/, '').split('|')
          value = false

          keys.each do |k|
            begin
              value = value != false ? value.send(k) : send(k)
            rescue
              value = ''
            end
          end

          case element.name
          when 'select'
            element.find('option') do |x|
              x['selected'] = true if x['value'] == value.to_s
            end
          when 'input'
            if %w(radio checkbox).include? element['type']
              if element['value'] == value.to_s
                element['checked'] = true
              else
                element.delete 'checked'
              end
            else
              value = sprintf('%.2f', value) if value.is_a? BigDecimal
              element['value'] = value.to_s
            end
          when 'textarea'
            element.val value.to_s
          end
        end
      end
    end
  end
end
