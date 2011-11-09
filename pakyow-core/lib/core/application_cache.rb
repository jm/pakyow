#TODO: rebuild cache after invalidating
#TODO: figure out how to cache partial responses (does this even make sense?)

#TODO: where should this live?
at_exit do
  Pakyow.app.app_cache.teardown 
end

module Pakyow
  class ApplicationCache
    def initialize
      self.connect
      @directives = { :store => [], :invalidate => [] }

      begin
        @cache_store = @cache.get "_cache_store"
      rescue
        @cache_store = []
      end
    end

    def finalize(data)
      @directives[:store].each do |d|
        begin
          key = d.key 
          puts "Storing #{key}"
          @cache.set key, data
          
          @cache_store << { :key => key, :path => d.path, :versions => d.versions, :constraints => d.constraints } 
        rescue Memcached::ServerIsMarkedDead
          #TODO: only attempt reconnecting a set number of times
          puts "Failed... reconnecting"
          self.connect(true)
          #TODO: delete stored keys, etc and read back out after connecting?
          redo
        end
      end
      
      @directives[:invalidate].each do |d|
        invalid_caches = @cache_store
        
        if p = d.invalid_path 
          invalid_caches = invalid_caches.select { |x| x[:path] == p }
        end
        
        if c = d.constraints
          invalid_caches = invalid_caches.select { |x| !(x[:constraints] - c).nil? }
        end
        
        if v = d.versions
          invalid_caches = invalid_caches.select { |x| !(x[:versions] - v).nil? }
        end

        invalid_caches.each do |c|
          self.invalidate_key c[:key]
        end
      end

      @directives = { :store => [], :invalidate => [] }
    end

    def invalidate_key(key, del = true)
      puts "Deleting #{key}"
      
      begin
        @cache.delete key

        return unless del
        @cache_store.delete_if {|c| c[:key] == key }
      rescue StandardError => e
        puts 'error deleting key'
        pp e
      end
    end

    def teardown
      @cache.set "_cache_store", @cache_store
    end
    
    def store(directive)
      @directives[:store] << directive
    end

    def invalidate(directive)
      @directives[:invalidate] << directive
    end

    def get(env)
      begin
        key = env['PATH_INFO'].dup
        
        if c = @cache_store.detect { |c| c[:path] == env['PATH_INFO'] } 
          r = Request.new(env)
          
          c[:versions].each do |v|
            key << r.send(v.keys.first)[v.values.first]
          end
        end
       
        @cache.get key
      rescue
        puts 'Cache not found'
      end
    end

    def connect(force = false)
      return if defined?(@cache) && !force
      @cache = Memcached.new("localhost:11211")
    end
  end
end

