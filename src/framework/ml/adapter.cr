require "./store"

module Cogni
  module ML
    abstract class Adapter
      getter id : String

      def initialize(@id : String)
      end

      abstract def train(
        model : ModelRecord,
        backend : String,
        dataset_id : String,
        items : Array(Cogni::Dataset::ItemRecord),
        config : AnyHash,
        ctx : Cogni::Workflow::NodeContext
      ) : AnyHash

      abstract def embed(
        model : ModelRecord,
        backend : String,
        texts : Array(String),
        config : AnyHash,
        ctx : Cogni::Workflow::NodeContext
      ) : AnyHash

      abstract def infer(
        model : ModelRecord,
        backend : String,
        inputs : Array(String),
        config : AnyHash,
        ctx : Cogni::Workflow::NodeContext
      ) : AnyHash

      abstract def eval(
        model : ModelRecord,
        backend : String,
        config : AnyHash,
        ctx : Cogni::Workflow::NodeContext
      ) : AnyHash
    end
  end
end
