# Registration of Orator node kinds
# This file is loaded by the framework to register custom node types

# Register send_to_inbox node kind
Ocawe::RegistryApi.node_kind("send_to_inbox") do |ctx, attributes|
  Orator::Translators::SendToInbox.translate(ctx.state, ctx.metadata)
end

# Register recevie_from_outbox node kind
Ocawe::RegistryApi.node_kind("recevie_from_outbox") do |ctx, attributes|
  Orator::Translators::ReceiveFromOutbox.translate(ctx.state, ctx.metadata)
end
