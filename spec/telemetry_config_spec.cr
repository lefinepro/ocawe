require "./spec_helper"
require "file_utils"

describe Ocawe::Telemetry do
  it "loads telemetry settings from rcl config" do
    path = File.tempname("ocawe-telemetry", ".rcl")
    File.write(path, <<-RCL)
      telemetry do
        enabled = true
        service_name = "ocawe-test"
        endpoint = "http://collector:4318"
        exporter = "stdout"
        tracesEnabled = true
        metricsEnabled = false
        logsEnabled = true
        sampleRatio = 0.5
      end
    RCL

    config = OcaweCore::Utils::ConfigParser.load_settings(Ocawe::Config::Settings.default, rcl_path: path)
    config.telemetry.enabled.should be_true
    config.telemetry.service_name.should eq("ocawe-test")
    config.telemetry.endpoint.should eq("http://collector:4318")
    config.telemetry.exporter.should eq("stdout")
    config.telemetry.metrics_enabled.should be_false
    config.telemetry.sample_ratio.should eq(0.5)
  ensure
    File.delete(path) if path && File.exists?(path)
  end

  it "loads telemetry settings from Cawfile settings" do
    dir = File.tempname("cawfile_telemetry")
    Dir.mkdir_p(dir)
    begin
      File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  telemetry do
    enabled = true
    service_name = "ocawe-caw"
    endpoint = "http://127.0.0.1:4318"
  end
end

workflow "telemetry-test" do
end
RCL
      bundle = ACD::Discovery::CawfileLoader.load(dir, "telemetry-test")
      bundle.not_nil!.config_telemetry["enabled"].should eq(true)
      bundle.not_nil!.config_telemetry["service_name"].should eq("ocawe-caw")
      settings = OcaweCore::Utils::ConfigParser.apply_cawfile_settings(Ocawe::Config::Settings.default, bundle.not_nil!)
      settings.telemetry.enabled.should be_true
      settings.telemetry.service_name.should eq("ocawe-caw")
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  it "records metrics and logs only when enabled" do
    Ocawe::Telemetry.configure(Ocawe::Config::TelemetrySettings.new)
    Ocawe::Telemetry.increment("disabled.metric")
    Ocawe::Telemetry.log("info", "disabled")
    Ocawe::Telemetry.metrics_snapshot.should be_empty
    Ocawe::Telemetry.logs_snapshot.should be_empty

    Ocawe::Telemetry.configure(
      Ocawe::Config::TelemetrySettings.new(
        enabled: true,
        traces_enabled: false,
      )
    )
    Ocawe::Telemetry.increment("enabled.metric", attributes: {"key" => "value"} of String => Ocawe::Telemetry::AttributeValue)
    Ocawe::Telemetry.log("info", "enabled", {"event.name" => "test"} of String => Ocawe::Telemetry::AttributeValue)
    Ocawe::Telemetry.metrics_snapshot.size.should eq(1)
    Ocawe::Telemetry.logs_snapshot.size.should eq(1)
  ensure
    Ocawe::Telemetry.configure(Ocawe::Config::TelemetrySettings.new)
  end
end
