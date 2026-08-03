require "json"

module TimerAgent
  extend self

  def handle(payload : Hash(String, JSON::Any)) : Hash(String, JSON::Any)
    now = now_unix(payload)
    action = action_from(payload)

    case action
    when "start_stopwatch"
      {
        "action"     => json_any(action),
        "status"     => json_any("running"),
        "started_at" => json_any(now),
        "now_unix"   => json_any(now),
        "message"    => json_any("stopwatch started"),
      }
    when "elapsed"
      started_at = int_value(payload["started_at"]?) || now
      elapsed = {now - started_at, 0_i64}.max
      {
        "action"          => json_any(action),
        "status"          => json_any("ok"),
        "started_at"      => json_any(started_at),
        "now_unix"        => json_any(now),
        "elapsed_seconds" => json_any(elapsed),
        "message"         => json_any("#{elapsed} seconds elapsed"),
      }
    when "set_timer"
      seconds = timer_seconds(payload)
      {
        "action"            => json_any(action),
        "status"            => json_any("scheduled"),
        "seconds"           => json_any(seconds),
        "started_at"        => json_any(now),
        "target_at"         => json_any(now + seconds),
        "remaining_seconds" => json_any(seconds),
        "message"           => json_any("timer set for #{seconds} seconds"),
      }
    when "set_alarm"
      target_at = alarm_target(payload, now)
      remaining = {target_at - now, 0_i64}.max
      {
        "action"            => json_any(action),
        "status"            => json_any("scheduled"),
        "started_at"        => json_any(now),
        "now_unix"          => json_any(now),
        "target_at"         => json_any(target_at),
        "remaining_seconds" => json_any(remaining),
        "message"           => json_any("alarm set for #{Time.unix(target_at).to_utc.to_rfc3339}"),
      }
    else
      {
        "action"   => json_any("now"),
        "status"   => json_any("ok"),
        "now_unix" => json_any(now),
        "iso_utc"  => json_any(Time.unix(now).to_utc.to_rfc3339),
      }
    end
  end

  def action_from(payload : Hash(String, JSON::Any)) : String
    explicit = string_value(payload["action"]?).downcase
    return explicit unless explicit.empty?

    text = string_value(payload["prompt"]?).downcase
    return "start_stopwatch" if text.matches?(/\b(start|set|begin)\b.*\b(stopwatch|секундомер)\b/)
    return "elapsed" if text.matches?(/\b(elapsed|passed|сколько|прошло)\b/)
    return "set_alarm" if text.matches?(/\b(alarm|будильник)\b/)
    return "set_timer" if text.matches?(/\b(timer|countdown|remind|секунд|таймер)\b/)
    "now"
  end

  def timer_seconds(payload : Hash(String, JSON::Any)) : Int64
    explicit = int_value(payload["seconds"]?)
    return explicit if explicit && explicit > 0

    text = string_value(payload["prompt"]?).downcase
    if match = text.match(/(\d+)\s*(seconds?|sec|s|секунд[уы]?)/)
      return match[1].to_i64
    end
    if match = text.match(/(\d+)\s*(minutes?|min|m|минут[уы]?)/)
      return match[1].to_i64 * 60
    end
    if match = text.match(/(\d+)\s*(hours?|hour|h|час[аов]?)/)
      return match[1].to_i64 * 3600
    end
    60_i64
  end

  def alarm_target(payload : Hash(String, JSON::Any), now : Int64) : Int64
    explicit = int_value(payload["target_at"]?) || int_value(payload["alarm_unix"]?)
    return explicit if explicit && explicit > now

    text = string_value(payload["prompt"]?).downcase
    if match = text.match(/\b(?:at|на|в)\s*(\d{1,2}):(\d{2})\b/)
      hour = match[1].to_i
      minute = match[2].to_i
      current = Time.unix(now).to_utc
      candidate = Time.utc(current.year, current.month, current.day, hour, minute, 0).to_unix
      candidate += 86_400_i64 if candidate <= now
      return candidate
    end
    now + timer_seconds(payload)
  end

  def now_unix(payload : Hash(String, JSON::Any)) : Int64
    int_value(payload["now_unix"]?) || Time.utc.to_unix
  end

  def int_value(value : JSON::Any?) : Int64?
    value.try(&.as_i64?) || value.try(&.as_i?).try(&.to_i64) || value.try(&.as_s?).try(&.to_i64?)
  end

  def string_value(value : JSON::Any?) : String
    value.try(&.as_s?) || ""
  end

  def json_any(value) : JSON::Any
    JSON.parse(value.to_json)
  end
end

Ocawe::RegistryApi.register_function("timer") do |ctx|
  payload = ctx.input_data.empty? ? ctx.state : ctx.input_data
  TimerAgent.handle(payload)
end
