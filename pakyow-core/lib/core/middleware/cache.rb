module Pakyow
  class Cache
    def initialize(app)
      @app = app
    end
    
    def call(env)
      if cached = Pakyow.app.app_cache.get(env)
        return cached
      end

      ret = Pakyow.app.call(env)
      Pakyow.app.app_cache.finalize([Pakyow.app.response.status, Pakyow.app.response.header, Pakyow.app.response.body])
      return ret
    end
  end
end

