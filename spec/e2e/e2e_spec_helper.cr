require "../spec_helper"
require "file_utils"

# Shared helpers for E2E test suite
#
# Configuration:
# - Model API: Configurable via COGNI_E2E_MODEL env var (default: clipproxyapi/qwen3-coder-model)
# - API keys: Stored in CLIPROXY_API_KEY secret
# - Mock mode: Set COGNICORE_MOCK_LLM=1 for unit testing without real API calls
#
# Usage:
#   # Run all E2E tests with mock (no API calls):
#   COGNICORE_MOCK_LLM=1 crystal spec spec/e2e/
#
#   # Run with real API (requires CLIPROXY_API_KEY):
#   crystal spec spec/e2e/

module E2ETestHelpers
  extend self

  # Default model for E2E tests - configurable via environment
  def default_model : String
    ENV["COGNI_E2E_MODEL"]? || "clipproxyapi/qwen3-coder-model"
  end

  # Check if we're in mock mode
  def mock_mode? : Bool
    ENV["COGNICORE_MOCK_LLM"]? == "1"
  end

  # Check if API key is available for real API tests
  def api_key_available? : Bool
    !ENV["CLIPROXY_API_KEY"]?.nil? && !ENV["CLIPROXY_API_KEY"]?.try(&.empty?)
  end

  # Check if we can run real API tests
  def can_run_real_api? : Bool
    mock_mode? || api_key_available?
  end

  # Create a temporary directory for test artifacts
  def with_temp_dir(&block : String ->)
    dir = "/tmp/ocawe_e2e_#{Random.rand(1_000_000)}"
    Dir.mkdir_p(dir)
    begin
      block.call(dir)
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
