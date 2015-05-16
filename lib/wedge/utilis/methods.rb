class Wedge
  module Methods
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def client?
        RUBY_ENGINE == 'opal'
      end

      def server?
        !client?
      end
    end

    def server?
      self.class.server?
    end

    def client?
      self.class.client?
    end
  end
end
