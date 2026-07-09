require "http/server"
require "json"

server = HTTP::Server.new do |context|
  case {context.request.method, context.request.path}
  when {"GET", "/weather"}
    context.response.content_type = "application/json"
    context.response.print({
      "location" => "demo-farm",
      "current" => {
        "temperature_2m" => 12.5,
        "wind_speed_10m" => 4.2,
      },
    }.to_json)
  when {"POST", "/farm/start"}
    body = context.request.body.try(&.gets_to_end).to_s
    puts "POST /farm/start"
    puts body

    context.response.content_type = "application/json"
    context.response.print({
      "started" => true,
      "received" => JSON.parse(body),
    }.to_json)
  else
    context.response.status_code = 404
    context.response.content_type = "application/json"
    context.response.print({"error" => "not found"}.to_json)
  end
end

address = server.bind_tcp("127.0.0.1", 5055)
puts "Mock API listening on http://#{address}"
server.listen
