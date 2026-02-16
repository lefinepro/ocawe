require "json"

module CogniCore
  module Workflow
    alias AnyHash = Hash(String, JSON::Any)

    enum RunStatus
      Running
      Success
      Failed
      Suspended
      Cancelled
    end

    enum NodeAction
      Continue
      Suspend
      Fail
    end

    enum NodeKind
      Agent
      Skill
      Tool
      Approve
      Fn
      Voice
      Rag
      Control
    end

    struct AgentResult
      include JSON::Serializable

      getter agent_type : String
      getter content : String
      getter metadata : AnyHash?
      getter provider : String?
      getter model : String?

      def initialize(
        @agent_type : String,
        @content : String,
        @metadata : AnyHash? = nil,
        @provider : String? = nil,
        @model : String? = nil
      )
      end

      def to_any_hash : AnyHash
        hash = {
          "agent_type" => JSON.parse(@agent_type.to_json),
          "content"    => JSON.parse(@content.to_json),
        } of String => JSON::Any
        hash["metadata"] = JSON.parse(@metadata.to_json) if @metadata
        hash["provider"] = JSON.parse(@provider.to_json) if @provider
        hash["model"] = JSON.parse(@model.to_json) if @model
        hash
      end
    end

    enum EventType
      RunStarted
      NodeStarted
      NodeCompleted
      RunSuspended
      RunCompleted
      RunFailed
      RunCancelled
      TimeTravelled
      Resumed
    end

    struct WorkflowError
      include JSON::Serializable

      getter type : String
      getter message : String

      def initialize(@type : String, @message : String)
      end
    end

    struct WorkflowOutputOptions
      include JSON::Serializable

      getter include_state : Bool
      getter include_resume_labels : Bool

      def initialize(@include_state : Bool = true, @include_resume_labels : Bool = true)
      end
    end

    struct WorkflowNodeResult
      include JSON::Serializable

      getter action : String
      getter data : AnyHash?
      getter error : WorkflowError?
      getter resume_labels : Array(String)?
      getter suspend_payload : AnyHash?

      def initialize(
        @action : String,
        @data : AnyHash? = nil,
        @error : WorkflowError? = nil,
        @resume_labels : Array(String)? = nil,
        @suspend_payload : AnyHash? = nil
      )
      end

      def self.continue(data : AnyHash? = nil)
        new(action: NodeAction::Continue.to_s.downcase, data: data)
      end

      def self.suspend(payload : AnyHash? = nil, resume_label : String? = nil, resume_labels : Array(String)? = nil)
        labels = resume_labels || (resume_label ? [resume_label] : nil)
        new(
          action: NodeAction::Suspend.to_s.downcase,
          suspend_payload: payload,
          resume_labels: labels,
        )
      end

      def self.fail(message : String, type : String = "node_error")
        new(
          action: NodeAction::Fail.to_s.downcase,
          error: WorkflowError.new(type, message),
        )
      end
    end

    struct WorkflowRunResult
      include JSON::Serializable

      getter run_id : String
      getter workflow_id : String
      getter status : String
      getter output : AnyHash?
      getter state : AnyHash?
      getter resume_labels : Array(String)?
      getter suspend_payload : AnyHash?
      getter error : WorkflowError?

      def initialize(
        @run_id : String,
        @workflow_id : String,
        @status : String,
        @output : AnyHash? = nil,
        @state : AnyHash? = nil,
        @resume_labels : Array(String)? = nil,
        @suspend_payload : AnyHash? = nil,
        @error : WorkflowError? = nil
      )
      end
    end

    struct WorkflowStreamEvent
      include JSON::Serializable

      getter type : String
      getter run_id : String
      getter workflow_id : String
      getter node_id : String?
      getter status : String
      getter message : String?
      getter payload : AnyHash?

      def initialize(
        @type : String,
        @run_id : String,
        @workflow_id : String,
        @status : String,
        @node_id : String? = nil,
        @message : String? = nil,
        @payload : AnyHash? = nil
      )
      end
    end

    struct WorkflowRunSnapshot
      include JSON::Serializable

      getter workflow_id : String
      getter run_id : String
      getter status : String
      getter state : AnyHash?
      getter output : AnyHash?
      getter init_data : AnyHash?
      getter node_results : Hash(String, AnyHash)?
      getter node_index : Int32
      getter resume_labels : Array(String)?
      getter suspend_payload : AnyHash?
      getter error : WorkflowError?
      getter resource_id : String?
      getter updated_at : String

      def initialize(
        @workflow_id : String,
        @run_id : String,
        @status : String,
        @state : AnyHash?,
        @output : AnyHash?,
        @init_data : AnyHash?,
        @node_results : Hash(String, AnyHash)?,
        @node_index : Int32,
        @resume_labels : Array(String)?,
        @suspend_payload : AnyHash?,
        @error : WorkflowError?,
        @resource_id : String?,
        @updated_at : String,
      )
      end
    end

    struct WorkflowRunOptions
      include JSON::Serializable

      getter run_id : String?
      getter resource_id : String?

      def initialize(@run_id : String? = nil, @resource_id : String? = nil)
      end
    end

    # Represents a scoped resource context for the unified use attribute
    struct ResourceScope
      getter model : String?
      getter skills : Array(String)?
      getter tools : Array(String)?

      def initialize(
        @model : String? = nil,
        @skills : Array(String)? = nil,
        @tools : Array(String)? = nil
      )
      end
    end
  end
end
