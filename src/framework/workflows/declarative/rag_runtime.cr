require "json"

module Ocawe
  module Workflow
    class RagRuntime
      record StoredDocument, id : String, text : String, metadata : AnyHash

      @@lock = Mutex.new
      @@indexes = {} of String => Array(StoredDocument)

      def self.execute(ctx : NodeContext, config : AnyHash) : AnyHash
        # Configuration parameters should come from node config, not from state
        operation = config_option(ctx, config, ["operation"], "")
        vector_store_name = config_option(ctx, config, ["vectorStoreName", "vector_store_name"], "memory")
        index_name = config_option(ctx, config, ["indexName", "index_name"], "#{ctx.workflow_id}_default")

        # Runtime data parameters can come from state, input_data, or config (in that order)
        query_text = string_option(ctx, config, ["queryText", "query_text", "query"], "")
        top_k = int_option(ctx, config, ["topK", "top_k"], 10)
        filter = hash_option(ctx, config, ["filter"])

        docs = collect_documents(ctx)
        metadata = hash_option(ctx, config, ["metadata"]) || ({} of String => JSON::Any)

        did_upsert = false
        if operation == "upsert" || (operation.empty? && !docs.empty?)
          upsert(index_name, docs, metadata)
          did_upsert = true
          return upsert_response(index_name, vector_store_name, docs.size) if operation == "upsert" || query_text.empty?
        end

        query_response(index_name, vector_store_name, query_text, top_k, filter, did_upsert)
      end

      private def self.upsert(index_name : String, docs : Array(String), metadata : AnyHash) : Nil
        return if docs.empty?

        @@lock.synchronize do
          existing = (@@indexes[index_name]? || [] of StoredDocument).dup
          docs.each_with_index do |text, idx|
            id = "doc_#{Time.utc.to_unix_ms}_#{idx}_#{Random.rand(100000)}"
            # Deep copy metadata to prevent shared state mutations
            metadata_copy = JSON.parse(metadata.to_json).as_h
            existing << StoredDocument.new(id, text, metadata_copy)
          end
          @@indexes[index_name] = existing
        end
      end

      private def self.query_response(
        index_name : String,
        vector_store_name : String,
        query_text : String,
        top_k : Int32,
        filter : AnyHash?,
        did_upsert : Bool
      ) : AnyHash
        docs = @@lock.synchronize { (@@indexes[index_name]? || [] of StoredDocument).dup }
        filtered = apply_filter(docs, filter)
        ranked = rank(filtered, query_text)
        selected = ranked.first(top_k)

        sources = selected.map do |entry|
          source = {} of String => JSON::Any
          source["id"] = any(entry[:doc].id)
          source["metadata"] = any(entry[:doc].metadata)
          source["vector"] = any([] of Float64)
          source["score"] = any(entry[:score])
          source["document"] = any(entry[:doc].text)
          any(source)
        end

        relevant_context = selected.map do |entry|
          meta = entry[:doc].metadata.dup
          meta["text"] = any(entry[:doc].text) unless meta.has_key?("text")
          any(meta)
        end

        answer = selected.first?.try(&.[:doc].text) || if query_text.empty?
                                                        "No query provided"
                                                      else
                                                        "No indexed document matched query"
                                                      end

        {
          "rag_status" => any("ok"),
          "operation" => any("query"),
          "vectorStoreName" => any(vector_store_name),
          "indexName" => any(index_name),
          "queryText" => any(query_text),
          "topK" => any(top_k),
          "relevantContext" => any(relevant_context),
          "sources" => any(sources),
          "answer" => any(answer),
          "documents_count" => any(docs.size),
          "rag_documents" => any(docs.map(&.text)),
          "did_upsert" => any(did_upsert),
        } of String => JSON::Any
      end

      private def self.upsert_response(index_name : String, vector_store_name : String, upserted_count : Int32) : AnyHash
        docs = @@lock.synchronize { (@@indexes[index_name]? || [] of StoredDocument).dup }
        {
          "rag_status" => any("ok"),
          "operation" => any("upsert"),
          "vectorStoreName" => any(vector_store_name),
          "indexName" => any(index_name),
          "upsertedCount" => any(upserted_count),
          "documents_count" => any(docs.size),
          "rag_documents" => any(docs.map(&.text)),
        } of String => JSON::Any
      end

      private def self.collect_documents(ctx : NodeContext) : Array(String)
        docs = [] of String

        legacy_docs = ctx.state["rag_documents"]?.try(&.as_a?)
        if legacy_docs
          legacy_docs.each do |item|
            if text = item.as_s?
              docs << text
            end
          end
        end

        append_document_value(docs, ctx.state["documents"]?)
        append_document_value(docs, ctx.input_data["documents"]?)
        append_document_value(docs, ctx.state["chunks"]?)
        append_document_value(docs, ctx.input_data["chunks"]?)
        append_document_value(docs, ctx.state["document"]?)
        append_document_value(docs, ctx.input_data["document"]?)
        append_document_value(docs, ctx.state["text"]?)
        append_document_value(docs, ctx.input_data["text"]?)

        docs.reject(&.empty?).uniq
      end

      private def self.append_document_value(target : Array(String), value : JSON::Any?) : Nil
        return unless value

        if as_s = value.as_s?
          target << as_s
          return
        end

        if as_h = value.as_h?
          if text = as_h["text"]?.try(&.as_s?)
            target << text
          elsif content = as_h["content"]?.try(&.as_s?)
            target << content
          elsif document = as_h["document"]?.try(&.as_s?)
            target << document
          end
          return
        end

        if as_a = value.as_a?
          as_a.each { |item| append_document_value(target, item) }
        end
      end

      private def self.apply_filter(docs : Array(StoredDocument), filter : AnyHash?) : Array(StoredDocument)
        return docs unless filter

        docs.select do |doc|
          filter.all? do |key, expected|
            actual = doc.metadata[key]?
            actual && actual.to_json == expected.to_json
          end
        end
      end

      private def self.rank(docs : Array(StoredDocument), query_text : String) : Array(NamedTuple(doc: StoredDocument, score: Float64))
        return docs.map { |doc| {doc: doc, score: 0.0} } if query_text.strip.empty?

        query = query_text.downcase
        terms = query.split(/\s+/).reject(&.empty?)

        scored = docs.map do |doc|
          body = doc.text.downcase
          score = 0.0
          score += 1.0 if body.includes?(query)
          terms.each do |term|
            score += 0.2 if body.includes?(term)
          end
          {doc: doc, score: score}
        end

        scored.sort_by { |entry| {-entry[:score], entry[:doc].id} }
      end

      private def self.config_option(ctx : NodeContext, config : AnyHash, keys : Array(String), default_value : String) : String
        keys.each do |key|
          if value = config[key]?.try(&.as_s?)
            return value
          end
        end
        default_value
      end

      private def self.string_option(ctx : NodeContext, config : AnyHash, keys : Array(String), default_value : String) : String
        keys.each do |key|
          if value = ctx.state[key]?.try(&.as_s?)
            return value
          end
          if value = ctx.input_data[key]?.try(&.as_s?)
            return value
          end
          if value = config[key]?.try(&.as_s?)
            return value
          end
        end
        default_value
      end

      private def self.config_int_option(ctx : NodeContext, config : AnyHash, keys : Array(String), default_value : Int32) : Int32
        keys.each do |key|
          value = config[key]?
          next unless value
          if i = value.as_i?
            return i
          end
          if f = value.as_f?
            return f.to_i
          end
          if s = value.as_s?
            parsed = s.to_i?
            return parsed if parsed
          end
        end
        default_value
      end

      private def self.int_option(ctx : NodeContext, config : AnyHash, keys : Array(String), default_value : Int32) : Int32
        keys.each do |key|
          value = ctx.state[key]? || ctx.input_data[key]? || config[key]?
          next unless value
          if i = value.as_i?
            return i
          end
          if f = value.as_f?
            return f.to_i
          end
          if s = value.as_s?
            parsed = s.to_i?
            return parsed if parsed
          end
        end
        default_value
      end

      private def self.config_hash_option(ctx : NodeContext, config : AnyHash, keys : Array(String)) : AnyHash?
        keys.each do |key|
          value = config[key]?
          next unless value
          if hash = value.as_h?
            return hash
          end
          if string = value.as_s?
            begin
              parsed = JSON.parse(string).as_h?
              return parsed if parsed
            rescue JSON::ParseException
            end
          end
        end
        nil
      end

      private def self.hash_option(ctx : NodeContext, config : AnyHash, keys : Array(String)) : AnyHash?
        keys.each do |key|
          value = ctx.state[key]? || ctx.input_data[key]? || config[key]?
          next unless value
          if hash = value.as_h?
            return hash
          end
          if string = value.as_s?
            begin
              parsed = JSON.parse(string).as_h?
              return parsed if parsed
            rescue JSON::ParseException
            end
          end
        end
        nil
      end

      private def self.any(value) : JSON::Any
        JSON.parse(value.to_json)
      end
    end
  end
end
