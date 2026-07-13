require "file_utils"
require "./spec_helper"

describe Ocawe::Files::Service do
  it "stores metadata, content, resources, and deletion state" do
    dir = File.tempname("ocawe_files_service")
    Dir.mkdir_p(dir)
    begin
      dataset_service = Ocawe::Dataset::Service.new
      service = Ocawe::Files::Service.new(dataset_service, dir)

      file = service.create("note.txt", "hello", "assistants")
      file["id"].as_s.should start_with("file_")
      file["filename"].as_s.should eq("note.txt")
      file["bytes"].as_i.should eq(5)

      file_id = file["id"].as_s
      service.get(file_id).not_nil!["filename"].as_s.should eq("note.txt")
      service.content(file_id).should eq("hello")
      service.resource(file_id).not_nil!["content_base64"].as_s.should_not be_empty
      service.list.map { |entry| entry["id"].as_s }.should contain(file_id)

      service.delete(file_id).should be_true
      service.get(file_id).should be_nil
      service.content(file_id).should be_nil
    ensure
      FileUtils.rm_rf(dir)
    end
  end
end
