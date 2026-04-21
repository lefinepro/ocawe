module ACD
  module Kemal
    class App
      private def merge_agents(
        global_agents : Array(ACD::Agents::LoadedAgent),
        local_agents : Array(ACD::Agents::LoadedAgent)
      ) : Array(ACD::Agents::LoadedAgent)
        merged = {} of String => ACD::Agents::LoadedAgent
        global_agents.each { |agent| merged[agent.id] = agent }
        local_agents.each { |agent| merged[agent.id] = agent }
        merged.values.to_a
      end

      private def register_configured_functions! : Nil
        config = @settings
        Cogni::RegistryApi.reset_all!

        config.functions.each do |name, handler|
          Cogni::RegistryApi.register_system_function(name, &handler)
        end
        config.workspace_bootstrap.try(&.call)
      end

      private def bootstrap_federation_subscriptions : Nil
        @settings.federation.auto_subscribe.each do |entry|
          normalized = entry.strip
          next if normalized.empty?

          begin
            record = Cogni::Federation::Subscriptions.ensure(@settings, @federation_store, normalized)
            STDERR.puts "[federation] subscribed #{normalized} -> #{record["remote_actor"]?.try(&.as_s?) || normalized}"
          rescue ex
            STDERR.puts "[federation] auto_subscribe failed for #{normalized}: #{ex.message || ex.class.name}"
          end
        end
      end

      private def build_dataset_store(config : Cogni::Config::DatasetSettings) : Cogni::Dataset::Store::Base
        case config.adapter.strip.downcase
        when "", "memory"
          Cogni::Dataset::Store::InMemory.new
        when "file"
          Cogni::Dataset::Store::File.new(config.file_root)
        else
          raise "unsupported dataset adapter: #{config.adapter}"
        end
      end

      private def build_ml_store(config : Cogni::Config::MLSettings) : Cogni::ML::Store::Base
        case config.registry_adapter.strip.downcase
        when "", "memory"
          Cogni::ML::Store::InMemory.new
        when "file"
          Cogni::ML::Store::File.new(config.file_root)
        else
          raise "unsupported ml registry adapter: #{config.registry_adapter}"
        end
      end

      private def build_federation_store(config : Cogni::Config::FederationSettings) : Cogni::Federation::Store::Base
        case config.adapter.strip.downcase
        when "", "memory"
          Cogni::Federation::Store::Memory.new
        when "sqlite"
          Cogni::Federation::Store::SQLite.new(config.sqlite_path)
        else
          raise "unsupported federation adapter: #{config.adapter}"
        end
      end
    end
  end
end
