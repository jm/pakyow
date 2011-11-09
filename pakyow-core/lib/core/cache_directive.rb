module Pakyow
  class CacheDirective
    attr_reader :path, :request, :invalid_path

    def initialize(request)
      @request = request
      pp request.path
      @path = request.path

      @versions = []
      @constraints = []
      
      self
    end

    def key
      key = @path.dup
      
      if @versions && !@versions.empty?
        @versions.each do |v|
          next if @request.route_spec.include?(":#{v.values.first}")
          next unless val = @request.send(v.keys.first)[v.values.first]
          key << val 
        end
      end

      key
    end

    def store
      Pakyow.app.app_cache.store(self)
    end

    def invalidate
      Pakyow.app.app_cache.invalidate(self)
    end

    def invalidate_for_route(route)
      @invalid_path = route
      Pakyow.app.app_cache.invalidate(self)
    end

    def versions(v = nil)
      if v.nil?
        return @versions
      end

      if v.is_a? Array
        @versions = @versions.concat v
      else
        @versions << v
      end
      
      self
    end

    def constraints(c = nil)
      if c.nil?
        return @constraints
      end
     
      if c.is_a? Array
        @constraints = @constraints.concat c
      else
        @constraints << c
      end
      
      self
    end
  end
end

