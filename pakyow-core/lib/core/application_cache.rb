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
         
          env = {
            'PATH_INFO' => d.request.env['PATH_INFO'],
            'REQUEST_METHOD' => d.request.env['REQUEST_METHOD'],
            'QUERY_STRING' => d.request.env['QUERY_STRING'],
            'rack.request.query_string' => d.request.env['rack.request.query_string'],
            'rack.request.query_hash' => d.request.env['rack.request.query_hash']
          }
          
          @cache_store << { 
            :key => key, 
            :path => d.path, 
            :versions => d.versions, 
            :constraints => d.constraints,
            :env => env
          }
        rescue Memcached::ServerIsMarkedDead
          #TODO: only attempt reconnecting a set number of times
          puts "Failed... reconnecting"
          self.connect(true)
          #TODO: delete stored keys, etc and read back out after connecting?
          redo
        end
      end
      
      to_rebuild = []
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

        to_rebuild = invalid_caches.dup
        
        # invalidate (deletes caches from memcached and the store)
        invalid_caches.each do |c|
          self.invalidate_key c[:key]
        end
      end

      @directives = { :store => [], :invalidate => [] }

      unless to_rebuild.empty?
        # rebuild caches
        thread = Thread.new do
          cache = @cache.clone
         
          to_rebuild.each do |c|
            env = Pakyow.app.request.env.dup.merge(c[:env])

            #TODO: use clone of application
            Pakyow.app.call(env)
            Pakyow.app.app_cache.finalize([Pakyow.app.response.status, Pakyow.app.response.header, Pakyow.app.response.body])
          end
        end

        thread.join
      end
    rescue StandardError => e
      pp e
      pp e.backtrace
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
      #TODO: why is there a nokogiri document object in the store?
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

