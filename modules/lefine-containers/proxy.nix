{ pkgs, pipelinesRoot ? ../../../sireng/pipelines, lib, ... }:

let
  mkOcaweWorkflowActor = import ./ocawe-workflow-actor.nix { inherit pkgs lib; };
in
mkOcaweWorkflowActor {
  name = "proxy";
  pipeline = "${pipelinesRoot}/proxy";
  hostPort = 8087;
  extraEnvironment = {
    AUTOPROXYGEN_FEDERATION_OUTBOX_URL = "\${AUTOPROXYGEN_FEDERATION_OUTBOX_URL:-http://autoproxygen:4077/users/autoproxygen/outbox?page=1}";
  };
}
