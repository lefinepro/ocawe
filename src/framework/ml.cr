require "./dataset/service"
require "./workflows/declarative/run"
require "./ml/store"
require "./ml/service"
require "./ml/adapter"
require "./ml/runtime"

module Cogni
  module ML
    @@service : Service?
    @@runtime : Runtime?

    def self.configure!(service : Service, runtime : Runtime) : Nil
      @@service = service
      @@runtime = runtime
    end

    def self.service : Service
      @@service ||= Service.new
    end

    def self.runtime : Runtime
      @@runtime ||= Runtime.new(service, Cogni::Dataset::Service.new)
    end

    def self.reset! : Nil
      @@service = nil
      @@runtime = nil
    end
  end
end
