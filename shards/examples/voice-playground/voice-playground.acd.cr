struct VoicePlaygroundInput
  include JSON::Serializable

  getter audio : String?
  getter text : String?
end

struct VoicePlaygroundOutput
  include JSON::Serializable

  getter text : String?
  getter audio_url : String?
end

workflow "voice-playground" do
  input_type VoicePlaygroundInput
  output_type VoicePlaygroundOutput

  input_validate Schema::Types.object({
    "audio" => Schema::Types.optional(Schema::Types.of(String)),
    "text" => Schema::Types.optional(Schema::Types.of(String)),
  })

  output_validate Schema::Types.object({
    "text" => Schema::Types.optional(Schema::Types.of(String)),
    "audio_url" => Schema::Types.optional(Schema::Types.of(String)),
  })

  agent "voice-agent", input_schema: schema_ref("input"), output_schema: schema_ref("output")
  skill "voice-transcribe-skill"
  voice "voice-transcribe"
  skill "voice-synthesize-skill"
  voice "voice-synthesize"
end
