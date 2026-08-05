class NbchannelPatch
  SRC = "lib/nbchannel/src/nbchannel.cr"
  SEARCH = "Crystal::Scheduler.reschedule"
  REPLACEMENT = "Fiber.yield"

  def self.apply
    return unless File.file?(SRC)

    source = File.read(SRC)
    updated = source.gsub(SEARCH, REPLACEMENT)
    return if updated == source

    File.write(SRC, updated)
  end
end

NbchannelPatch.apply
