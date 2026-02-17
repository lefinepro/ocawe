require "http/client"
require "../cognicore/workflow/run"

module Cogni
  class Workflow < CogniCore::Workflow::WorkflowDefinition
    def self.build(id : String, description : String? = nil) : self
      new(id, description)
    end
  end

  class Trigger
    @base_url : String

    def initialize(@base_url : String = "http://localhost:4111")
    end

    def workflow(id : String) : Target
      Target.new(@base_url, "workflows", id)
    end

    def agent(id : String) : Target
      Target.new(@base_url, "agents", id)
    end

    def skill(id : String) : Target
      Target.new(@base_url, "skills", id)
    end

    def function(id : String) : Target
      Target.new(@base_url, "functions", id)
    end

    class Target
      @base_url : String
      @kind : String
      @id : String

      def initialize(@base_url : String, @kind : String, @id : String)
      end

      def run(payload : CogniCore::Workflow::AnyHash = {} of String => JSON::Any) : JSON::Any
        url = "#{trimmed_base_url}/v1/triggers/#{@kind}/#{@id}"
        response = HTTP::Client.post(url, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: payload.to_json)
        JSON.parse(response.body)
      end

      private def trimmed_base_url : String
        @base_url.ends_with?("/") ? @base_url[0, @base_url.size - 1] : @base_url
      end
    end
  end
end
