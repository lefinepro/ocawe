require "json"

module Api
  module ACP
    # Marker module for ACP agent support.
    # Including this in a Cawfile struct enables the ACP agent endpoint
    # for this workflow, allowing external ACP clients to connect.
    #
    # Usage in Cawfile:
    #   struct Input
    #     include Api::ACP::Agent
    #   end
    #   struct Output
    #     include Api::ACP::Agent
    #   end
    #
    # This enables the workflow to act as an ACP agent server,
    # exposing JSON-RPC endpoints over stdio or HTTP.
    module Agent
      include JSON::Serializable

      # ACP protocol version (negotiated during initialization)
      property acp_protocol_version : Int32?

      # Agent capabilities advertised during initialization
      property acp_capabilities : Hash(String, JSON::Any)?

      # Client info from the connecting ACP client
      property acp_client_name : String?
      property acp_client_version : String?

      # Session ID for the ACP session
      property acp_session_id : String?

      # The prompt content received from the client
      property acp_prompt : Array(Hash(String, JSON::Any))?

      # Response content to send back to the client
      property acp_response : Array(Hash(String, JSON::Any))?

      # Tool calls requested by the agent
      property acp_tool_calls : Array(Hash(String, JSON::Any))?

      # Stop reason for the turn
      property acp_stop_reason : String?
    end
  end
end
