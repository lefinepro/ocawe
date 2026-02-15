require "file_utils"
require "http/client"

require "../config/acd_config"

module CogniCore
  module Runtime
    struct RuntimeSpec
      getter language : String
      getter runtime_url : String
      getter version : String
      getter entrypoint : String

      def initialize(@language : String, @runtime_url : String, @version : String, @entrypoint : String)
      end
    end

    struct RuntimeConfig
      getter runtimes : Array(RuntimeSpec)
      getter download_path : String

      def initialize(@runtimes : Array(RuntimeSpec) = [] of RuntimeSpec, @download_path : String = "runtime_cache")
      end
    end

    class RuntimeManager
      def initialize
      end

      def install_all
        config = load_config
        FileUtils.mkdir_p(config.download_path)

        config.runtimes.each do |spec|
          install(spec, config.download_path)
        end
      end

      def install(spec : RuntimeSpec, download_path : String)
        target = File.join(download_path, "#{spec.language}-#{spec.version}")
        archive = "#{target}.bin"
        return if File.exists?(target)

        puts "[runtime] downloading #{spec.language}@#{spec.version} from #{spec.runtime_url}"

        response = HTTP::Client.get(spec.runtime_url)
        raise "download failed: #{spec.runtime_url} (#{response.status_code})" unless response.success?

        File.write(archive, response.body)
        FileUtils.mkdir_p(target)
        File.write(File.join(target, "ENTRYPOINT"), spec.entrypoint)
        File.write(File.join(target, "RUNTIME_URL"), spec.runtime_url)
        File.write(File.join(target, "VERSION"), spec.version)
      end

      private def load_config
        acd = CogniCore::Config::ACDConfig.settings.runtime
        runtimes = acd.runtimes.map do |spec|
          RuntimeSpec.new(
            language: spec.language,
            runtime_url: spec.runtime_url,
            version: spec.version,
            entrypoint: spec.entrypoint,
          )
        end
        RuntimeConfig.new(runtimes: runtimes, download_path: acd.download_path)
      end
    end
  end
end
