require "http/client"
require "json"
require "uri"

module FmatchTagger
  extend self

  DEFAULT_LABELS = %w[
    code debug deploy research weather search timer planning cheap fast reasoning
    long-context vision writing translation data api database frontend backend
  ]
  FMATCH_ACTOR = ENV["FMATCH_ACTOR_ID"]? || "@planner@fmatch.internal.fedi"
  TAGGER_ACTOR = ENV["TAGGER_ACTOR_ID"]? || "http://tagger:4112/actors/tagger"
  FMATCH_INBOX_URL = ENV["FMATCH_INBOX_URL"]? || "http://fmatch:7277/inbox/planner"
  MODEL_RESOURCE = "https://fmatch/marketplace/resources/model"

  record Classification, tags : Array(String), confidence : Float64, route : String

  def handle(payload : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
    text = text_from(payload)
    labels = labels_from(payload)
    classification = classify(text, labels)
    model_hints = model_hints(classification.tags)
    agent_hints = agent_hints(classification.tags)
    output = {
      "tags"          => json_any(classification.tags),
      "confidence"    => json_any(classification.confidence),
      "route"         => json_any(classification.route),
      "model_hints"   => json_any(model_hints),
      "agent_hints"   => json_any(agent_hints),
      "fmatch_posted" => json_any(false),
    }

    if should_ask_fmatch?(classification)
      proposal = model_tagging_proposal(text, labels)
      output["fmatch_proposal"] = json_any(proposal)
      if response = post_to_fmatch(proposal)
        output["fmatch_posted"] = json_any(true)
        output["fmatch_response"] = json_any(response)
      end
    end

    output
  end

  def classify(text : String, labels : Array(String) = DEFAULT_LABELS) : Classification
    normalized = text.downcase
    tags = [] of String

    add_if(tags, labels, "code", normalized, /\b(code|coding|program|implement|refactor|crystal|rust|typescript|python|api)\b/)
    add_if(tags, labels, "debug", normalized, /\b(debug|bug|failure|failing|stacktrace|ошибка|фикс|почини)\b/)
    add_if(tags, labels, "deploy", normalized, /\b(deploy|release|production|container|systemd|nix|docker|migration|rollback)\b/)
    add_if(tags, labels, "research", normalized, /\b(research|analyze|compare|investigate|audit|исслед|анализ)\b/)
    add_if(tags, labels, "weather", normalized, /\b(weather|forecast|temperature|rain|погода|прогноз)\b/)
    add_if(tags, labels, "search", normalized, /\b(search|find|lookup|web|найди|поиск)\b/)
    add_if(tags, labels, "timer", normalized, /\b(timer|stopwatch|countdown|time|секундомер|таймер|время)\b/)
    add_if(tags, labels, "planning", normalized, /\b(plan|schedule|roadmap|break down|план)\b/)
    add_if(tags, labels, "cheap", normalized, /\b(cheap|free|low cost|дешев|бесплат)\b/)
    add_if(tags, labels, "fast", normalized, /\b(fast|quick|low latency|быстро|срочно)\b/)
    add_if(tags, labels, "reasoning", normalized, /\b(reason|reasoning|think|thinking|complex|math|architecture|сложн)\b/)
    add_if(tags, labels, "long-context", normalized, /\b(long context|large file|whole repo|много контекста)\b/)
    add_if(tags, labels, "vision", normalized, /\b(image|screenshot|photo|vision|картин|скрин)\b/)
    add_if(tags, labels, "writing", normalized, /\b(write|rewrite|copy|essay|draft|текст|напиши)\b/)
    add_if(tags, labels, "translation", normalized, /\b(translate|translation|переведи|перевод)\b/)
    add_if(tags, labels, "data", normalized, /\b(data|dataset|sql|analytics|csv|jsonl|данн)\b/)
    add_if(tags, labels, "frontend", normalized, /\b(frontend|ui|css|svelte|react|astro|верстк)\b/)
    add_if(tags, labels, "backend", normalized, /\b(backend|server|database|postgres|endpoint|worker)\b/)
    add_if(tags, labels, "database", normalized, /\b(database|postgres|sqlite|sql|migration|db)\b/)
    add_if(tags, labels, "api", normalized, /\b(api|endpoint|webhook|http|rest|graphql)\b/)

    tags << "general" if tags.empty? && labels.includes?("general")
    confidence = tags.empty? || tags == ["general"] ? 0.25 : {0.45 + tags.size * 0.12, 0.92}.min
    route = route_for(tags, confidence)
    Classification.new(tags.uniq, confidence, route)
  end

  def model_hints(tags : Array(String)) : Array(String)
    hints = [] of String
    hints << "small-free" if tags.includes?("cheap") || tags.includes?("fast")
    hints << "reasoning" if tags.includes?("reasoning") || tags.includes?("research")
    hints << "coding" if tags.includes?("code") || tags.includes?("debug")
    hints << "long-context" if tags.includes?("long-context")
    hints << "vision" if tags.includes?("vision")
    hints << "general" if hints.empty?
    hints.uniq
  end

  def agent_hints(tags : Array(String)) : Array(String)
    hints = [] of String
    hints << "openmeteo" if tags.includes?("weather")
    hints << "seacher" if tags.includes?("search")
    hints << "timer" if tags.includes?("timer")
    hints << "executor" if tags.includes?("code") || tags.includes?("debug")
    hints << "planner" if tags.includes?("planning")
    hints << "rotator" if hints.empty? || tags.includes?("reasoning") || tags.includes?("cheap") || tags.includes?("fast")
    hints.uniq
  end

  def model_tagging_proposal(text : String, labels : Array(String)) : Hash(String, JSON::Any)
    id = "#{TAGGER_ACTOR}/requests/#{stable_id(text)}"
    content = String.build do |io|
      io << "Return compact JSON only: {\"tags\":[...],\"model_hints\":[...],\"agent_hints\":[...],\"confidence\":number}.\n"
      io << "Allowed tags: #{labels.join(", ")}.\n\n"
      io << "Request:\n#{text}"
    end

    JSON.parse({
      "@context" => marketplace_context,
      "id" => id,
      "type" => "Create",
      "actor" => TAGGER_ACTOR,
      "to" => [FMATCH_ACTOR],
      "object" => {
        "id" => "#{id}#proposal",
        "type" => "Proposal",
        "purpose" => "request",
        "attributedTo" => TAGGER_ACTOR,
        "to" => [FMATCH_ACTOR],
        "name" => "Tag request",
        "content" => content,
        "mediaType" => "text/plain",
        "publishes" => {
          "id" => "#{id}#intent",
          "type" => "Intent",
          "action" => "deliverService",
          "receiver" => TAGGER_ACTOR,
          "resourceConformsTo" => MODEL_RESOURCE,
          "resourceQuantity" => {
            "hasUnit" => "one",
            "hasNumericalValue" => "1",
          },
        },
        "attachment" => [
          {"type" => "PropertyValue", "name" => "tagger", "value" => "fmatch-tagger"},
          {"type" => "PropertyValue", "name" => "resourceConformsTo", "value" => MODEL_RESOURCE},
        ],
      },
    }.to_json).as_h
  end

  def text_from(payload : Hash(String, JSON::Any)) : String
    prompt = string_value(payload["prompt"]?)
    return prompt unless prompt.empty?

    activity = payload["activity"]?.try(&.as_h?)
    object = activity.try(&.[]?("object")).try(&.as_h?)
    content = string_value(object.try(&.[]?("content")))
    content = string_value(object.try(&.[]?("summary"))) if content.empty?
    content = string_value(activity.try(&.[]?("content"))) if content.empty?
    content
  end

  private def route_for(tags : Array(String), confidence : Float64) : String
    return "fmatch-model" if confidence < 0.55
    return "fmatch-model" if tags.size > 3 && (tags.includes?("reasoning") || tags.includes?("research"))
    return "agent:timer" if tags.includes?("timer")
    return "agent:openmeteo" if tags.includes?("weather")
    return "agent:seacher" if tags.includes?("search")
    return "agent:executor" if tags.includes?("code") || tags.includes?("debug")
    "agent:rotator"
  end

  private def should_ask_fmatch?(classification : Classification) : Bool
    classification.route == "fmatch-model"
  end

  private def labels_from(payload : Hash(String, JSON::Any)) : Array(String)
    labels = payload["labels"]?.try(&.as_a?) || [] of JSON::Any
    parsed = labels.compact_map(&.as_s?)
    parsed.empty? ? DEFAULT_LABELS : parsed
  end

  private def add_if(tags : Array(String), labels : Array(String), tag : String, text : String, pattern : Regex) : Nil
    tags << tag if labels.includes?(tag) && text.matches?(pattern)
  end

  private def post_to_fmatch(activity : Hash(String, JSON::Any)) : JSON::Any?
    uri = URI.parse(FMATCH_INBOX_URL)
    response = HTTP::Client.new(uri) do |client|
      client.connect_timeout = 5.seconds
      client.read_timeout = 20.seconds
      client.write_timeout = 5.seconds
      client.post(
        uri.request_target,
        headers: HTTP::Headers{"Content-Type" => "application/activity+json", "Accept" => "application/json, application/activity+json"},
        body: activity.to_json
      )
    end
    return nil unless response.status_code.in?(200..299)
    body = response.body.to_s
    body.empty? ? nil : JSON.parse(body)
  rescue ex
    STDERR.puts "fmatch tagger post failed: #{ex.message || ex.class.name}"
    nil
  end

  private def marketplace_context : Array(JSON::Any)
    JSON.parse([
      "https://www.w3.org/ns/activitystreams",
      "https://w3id.org/fep/0837",
      {
        "om2" => "http://www.ontology-of-units-of-measure.org/resource/om-2/",
        "vf" => "https://w3id.org/valueflows/ont/vf#",
        "Proposal" => "vf:Proposal",
        "Intent" => "vf:Intent",
        "action" => "vf:action",
        "receiver" => {"@id" => "vf:receiver", "@type" => "@id"},
        "purpose" => "vf:purpose",
        "publishes" => {"@id" => "vf:publishes", "@type" => "@id"},
        "resourceConformsTo" => {"@id" => "vf:resourceConformsTo", "@type" => "@id"},
        "resourceQuantity" => "vf:resourceQuantity",
        "hasUnit" => "om2:hasUnit",
        "hasNumericalValue" => "om2:hasNumericalValue",
      },
    ].to_json).as_a
  end

  private def stable_id(value : String) : String
    value.hash.abs.to_s(36)
  end

  private def string_value(value : JSON::Any?) : String
    value.try(&.as_s?) || ""
  end

  private def json_any(value) : JSON::Any
    JSON.parse(value.to_json)
  end
end

Ocawe::RegistryApi.register_function("tagger", alias_name: "ocawe_handle_aptok_inbox_activity") do |ctx|
  payload = ctx.input_data.empty? ? ctx.state : ctx.input_data
  FmatchTagger.handle(payload)
end
