require "aptok"

# Ocawe's request/reply ActivityPub workflows need the remote inbox response,
# while Aptok's standard `deliver!` API intentionally returns the activity ID.
class Aptok::Transport
  def deliver_response!(delivery : Aptok::DeliveryConfig, activity : Aptok::JsonMap, key_pair : Aptok::ActorKeyPair? = nil) : Aptok::PostResponse
    payload = activity.to_json
    headers = HTTP::Headers{
      "Content-Type" => Aptok::FEDERATION_JSONLD_CONTENT_TYPE,
      "Accept"       => Aptok::FEDERATION_JSONLD_CONTENT_TYPE,
    }
    delivery.headers.each { |key, value| headers[key] = value }

    signature_headers = build_signature_headers("post", delivery.inbox, payload, key_pair)
    signature_headers.each { |key, value| headers[key] = value }

    response = post_payload(delivery.inbox, headers, payload)
    response = retry_accept_signature_challenge(delivery, payload, headers, response, key_pair)
    unless response.status_code >= 200 && response.status_code < 300
      message = response.body.empty? ? "activitypub inbox delivery failed" : "activitypub inbox delivery failed: #{response.body}"
      raise Aptok::DeliveryError.new(message, response.status_code)
    end

    response
  rescue ex : Aptok::DeliveryError
    raise ex
  rescue ex
    raise Aptok::DeliveryError.new("activitypub inbox delivery failed: #{ex.message}")
  end
end
