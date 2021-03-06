require 'wedge/require'

class Wedge
  class Component
    include Methods

    class << self
      attr_accessor :wedge_on_count

      def wedge_new(klass, *args, &block)
        obj = allocate

        %w(store scope).each do |meth|
          if value = klass.send(meth)
            obj.config.send "#{meth}=", value
          end
        end

        unless RUBY_ENGINE == 'opal'
          obj.config.on_compile.each do |blk|
            obj.instance_exec &blk
          end
        end

        if args.length > 0
          obj.config.initialize_args = args
          obj.send :initialize, *args, &block
        else
          obj.send :initialize, &block
        end

        obj
      end

      alias_method :original_name, :name
      def wedge_name(*args)
        if args.any?
          unless RUBY_ENGINE == 'opal'
            # set the file path
            path = "#{caller[0]}".gsub(/(?<=\.rb):.*/, '')
              .gsub(%r{(#{Dir.pwd}/#{Wedge.config.app_dir}/|.*(?=wedge))}, '')
              .gsub(/\.rb$/, '')
          end

          @wedge_on_count = 0

          args.each do |name|
            # set the name
            wedge_config.name = name

            unless RUBY_ENGINE == 'opal'
              # set the file path
              wedge_config.path = path
              # add it to the component class list allow path or name
              Wedge.config.component_class[path.gsub(/\//, '__')] = self
            end

            Wedge.config.component_class[name] = self
          end
        else
          original_name
        end
      end
      alias_method :name, :wedge_name

      def wedge_html(html = '', &block)
        unless RUBY_ENGINE == 'opal'
          wedge_config.html = begin
            File.read html
          rescue
            (html.is_a?(HTML::DSL) || html.is_a?(DOM)) ? html.to_html : html
          end.strip

          if block_given?
            yield
          end
        end
      end
      alias_method :html, :wedge_html

      # Set templates
      #
      # @example
      #   tmpl :some_name, dom.find('#some-div')
      # @return dom [DOM]
      def wedge_tmpl(name, dom = false, remove = true)
        if dom
          dom = remove ? dom.remove : dom
          wedge_config.tmpl[name] = {
            dom:  dom,
            html: dom.to_html
          }
        elsif t = wedge_config.tmpl[name]
          dom = DOM.new t[:html]
        else
          false
        end

        dom
      end
      alias_method :tmpl, :wedge_tmpl

      def wedge_dom &block

        unless RUBY_ENGINE == 'opal'
          if block_given?
            yield
          end
        end

        @wedge_dom ||= DOM.new wedge_config.html
      end
      alias_method :dom, :wedge_dom

      def wedge_config
        @wedge_config ||= Config.new Wedge.config.data.dup.merge(klass: self)
      end
      alias_method :config, :wedge_config

      def wedge_on(*args, &block)
        case args.first.to_s
        when 'server'
          wedge_on_server(&block)
        when 'compile'
          wedge_config.on_compile << block unless RUBY_ENGINE == 'opal'
        else
          @wedge_on_count += 1
          Wedge.events.add(config.name, *args, &block)
        end
      end
      alias_method :on, :wedge_on

      def method_missing(method, *args, &block)
        if wedge_config.scope.respond_to?(method, true)
          wedge_config.scope.send method, *args, &block
        else
          super
        end
      end

      def wedge_on_server(&block)
        if server?
          m = Module.new(&block)

          yield

          m.public_instance_methods(false).each do |meth|
            config.server_methods << meth.to_s

            alias_method :"wedge_on_server_#{meth}", :"#{meth}"
            define_method "#{meth}" do |*args, &blk|
              o_name = "wedge_on_server_#{meth}"

              if method(o_name).parameters.length > 0
                result = send(o_name, *args, &block)
              else
                result = send(o_name, &block)
              end

              blk ? blk.call(result) : result
            end
          end
        else
          m = Module.new(&block)

          m.public_instance_methods(false).each do |meth|
            config.server_methods << meth.to_s

            define_method "#{meth}" do |*args, &blk|
              path_name = config.path

              payload = config.client_data.reject do |k, _|
                %w(html tmpl requires plugins object_events js_loaded).include? k
              end
              payload[:__wedge_name__]   = payload[:name]
              payload[:__wedge_method__] = meth
              payload[:__wedge_args__]   = args

              # we want to remove the assets key from the call so we don't get
              # an error if they assets_key has changed and the user hasn't
              # refreshed the browser yet.
              call_url = "#{Wedge.assets_url.sub("#{Wedge.config.assets_key}/",'')}/#{path_name}.call"

              HTTP.post(call_url,
                headers: {
                  'X-CSRF-TOKEN' => Element.find('meta[name=_csrf]').attr('content'),
                  'X-WEDGE-METHOD-REQUEST' => true
                },
                payload: payload) do |response|

                  # We set the new csrf token
                  xhr  = Native(response.xhr)
                  csrf = xhr.getResponseHeader('WEDGE-CSRF-TOKEN')
                  Element.find('meta[name=_csrf]').attr 'content', csrf
                  ###########################

                  res = JSON.from_object(`response`)

                  blk.call res[:body], res
              end

              true
            end
          end

          include m
        end
      end

      def set_dom dom
        @wedge_dom = dom.is_a?(Wedge::DOM) ? dom : Wedge::DOM.new(dom)
      end

      def html!(&b)
        Wedge.html!(self, &b)
      end

      def store
        wedge_config.store
      end
    end

    if RUBY_ENGINE == 'opal'
      def wedge(*args)
        Wedge[*args]
      end

      def wedge_plugin(name, *args, &block)
        wedge("#{name}_plugin", *args, &block)
      end
    end

    def wedge_scope
      wedge_config.scope
    end
    alias_method :scope, :wedge_scope

    def wedge_store
      wedge_config.store
    end
    alias_method :store, :wedge_store

    def wedge_class_store
      self.class.wedge_config.store
    end
    alias_method :class_store, :wedge_class_store

    # Duplicate of class condig [Config]
    # @return config [Config]
    def wedge_config
      @wedge_config ||= Config.new(self.class.wedge_config.data.dup)
    end
    alias_method :config, :wedge_config

    # Grab a copy of the template
    # @return dom [DOM]
    def wedge_tmpl(name)
      self.class.wedge_tmpl name
    end
    alias_method :tmpl, :wedge_tmpl

    # Dom
    # @return wedge_dom [Dom]
    def wedge_dom
      @wedge_dom ||= begin
        if server?
          DOM.new self.class.wedge_dom.to_html
        else
          DOM.new(Element)
        end
      end
    end
    alias_method :dom, :wedge_dom

    # Special method that acts like the javascript equivalent
    # @example
    #   foo = {
    #     bar: function { |moo|
    #       moo.call 'something'
    #     }
    #   }.to_n
    def wedge_function(*args, &block)
      args.any? && raise(ArgumentError, '`function` does not accept arguments')
      block || raise(ArgumentError, 'block required')
      proc do |*a|
        a.map! {|x| Native(`x`)}
        @this = Native(`this`)
        %x{
         var bs = block.$$s,
            result;
          block.$$s = null;
          result = block.apply(self, a);
          block.$$s = bs;

          return result;
        }
      end
    end
    alias_method :function, :wedge_function

    def wedge_from_server?
      !scope.respond_to?(:request) || (request && !request.env.include?('HTTP_X_WEDGE_METHOD_REQUEST'))
    end
    alias_method :from_server?, :wedge_from_server?

    def wedge_from_client?
      !wedge_from_server?
    end
    alias_method :from_client?, :wedge_from_client?

    def wedge_javascript(method = false, *args)
      return unless server?

      client_data = config.client_data.dup
      client_data.merge!(
        method_called: method,
        method_args: args,
        initialize_args: config.initialize_args
      )

      compiled_opts = Base64.encode64 client_data.to_json
      javascript = <<-JS
        Wedge.javascript('#{config.path}', JSON.parse(Base64.decode64('#{compiled_opts}')))
      JS
      "<script>#{Opal.compile(javascript)}</script>"
    end
    alias_method :javscript, :wedge_javascript

    def wedge_trigger(event_name, *args)
      Wedge.events.trigger config.name, event_name, *args
    end
    alias_method :trigger, :wedge_trigger

    def to_js(method = false, *args)
      response = args.any? ? send(method, *args) : send(method)
      response = response.to_html if response.is_a? DOM
      response << wedge_javascript(method, *args) if response.is_a? String
      response
    end

    def wedge_html(&b)
      Wedge.html!(self, &b)
    end
    alias_method :html!, :wedge_html

    def method_missing(method, *args, &block)
      if config.scope.respond_to?(method, true)
        config.scope.send method, *args, &block
      else
        super
      end
    end
  end
end
