module ACD
  module Kemal
    class App
      private def federation_metadata_document : Hash(String, JSON::Any)
        {
          "@context" => JSON.parse(Aptok::ACTIVITYSTREAMS_CONTEXT.to_json),
          "protocols" => JSON.parse([Aptok::ACTIVITYSTREAMS_CONTEXT, Aptok::FORGEFED_CONTEXT, "http-signature"].to_json),
          "forgefed_context" => JSON.parse(Aptok::FORGEFED_CONTEXT.to_json),
          "supported_feps" => JSON.parse(supported_feps_metadata.to_json),
          "routes" => JSON.parse({
            "actor" => "/actors/{identifier}",
            "inbox" => "/actors/{identifier}/inbox",
            "outbox" => "/actors/{identifier}/outbox",
            "shared_inbox" => "/inbox",
          }.to_json),
        }
      end

      private def supported_feps_metadata : Array(JSON::Any)
        path = federation_markdown_path
        return [] of JSON::Any unless File.exists?(path)
        content = File.read(path)
        matches = content.scan(FEP_MARKDOWN_LINK_PATTERN)
        seen = Set(String).new
        entries = [] of JSON::Any
        matches.each do |match|
          label = match[1]?.to_s
          url = match[2]?.to_s
          next if label.empty? || url.empty?
          id = fep_id_from_markdown(label, url)
          next if id.empty?
          canonical_id = id.upcase
          next if seen.includes?(canonical_id)
          seen.add(canonical_id)
          entries << JSON.parse({"id" => canonical_id, "title" => fep_title_from_markdown(label, canonical_id), "url" => url}.to_json)
        end
        entries
      end

      private def federation_markdown_path : String
        explicit = ENV[FEDERATION_METADATA_ENV_VAR]?
        return File.expand_path(explicit, Dir.current) unless explicit.nil? || explicit.empty?
        File.expand_path("FEDERATION.md", Dir.current)
      end

      private def fep_id_from_markdown(label : String, url : String) : String
        if match = label.match(FEP_ID_PATTERN)
          return match[0].upcase
        end
        if match = url.match(FEP_FILE_ID_PATTERN)
          return "FEP-#{match[1].upcase}"
        end
        ""
      end

      private def fep_title_from_markdown(label : String, id : String) : String
        fallback_title = label.gsub(/\s+/, " ").strip
        prefix_pattern = Regex.new("^#{Regex.escape(id)}\\s*:?\\s*", Regex::Options::IGNORE_CASE)
        without_id = fallback_title.sub(prefix_pattern, "")
        without_id.empty? ? id : without_id.strip
      end
    end
  end
end
