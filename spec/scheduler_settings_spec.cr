require "file_utils"
require "./spec_helper"

describe "scheduler settings" do
  it "loads nested settings.scheduler from Cawfile" do
    dir = File.tempname("ocawe_scheduler_settings")
    Dir.mkdir_p(dir)
    begin
      File.write(File.join(dir, "Cawfile"), <<-RCL)
settings do
  scheduler do
    enabled = true
    min_workers = 0
    max_workers = 8
    target_queue_depth = 3
    scale_up_cooldown_ms = 25
    scale_down_cooldown_ms = 250
  end
end
RCL

      bundle = ACD::Discovery::CawfileLoader.load_root(dir)
      bundle.should_not be_nil
      settings = OcaweCore::Utils::ConfigParser.apply_cawfile_settings(Ocawe::Config::Settings.default, bundle.not_nil!)

      settings.scheduler.enabled.should be_true
      settings.scheduler.min_workers.should eq(0)
      settings.scheduler.max_workers.should eq(8)
      settings.scheduler.target_queue_depth.should eq(3)
      settings.scheduler.scale_up_cooldown_ms.should eq(25)
      settings.scheduler.scale_down_cooldown_ms.should eq(250)
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
