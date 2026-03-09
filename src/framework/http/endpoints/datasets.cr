require "./datasets/support"
require "./datasets/catalog"
require "./datasets/items"

module ACD
  module Kemal
    class App
      private def mount_dataset_endpoints
        mount_dataset_catalog_endpoints
        mount_dataset_item_endpoints
      end
    end
  end
end
