require "./spec_helper"

describe Ocawe::Workflow::Scheduler::Manager do
  it "queues work and scales a worker for pending load" do
    completed = Channel(String).new
    settings = Ocawe::Config::SchedulerSettings.new(
      enabled: true,
      min_workers: 0,
      max_workers: 2,
      target_queue_depth: 1,
      scale_up_cooldown_ms: 0,
      scale_down_cooldown_ms: 20,
    )
    scheduler = Ocawe::Workflow::Scheduler::Manager.new(
      settings,
      ->(job : Ocawe::Workflow::Scheduler::Job) { completed.send(job.run_id) }
    )

    status = scheduler.enqueue(Ocawe::Workflow::Scheduler::Job.new("wf", "run-1"))
    status.pending.should eq(1)
    status.workers.should eq(1)

    received = nil.as(String?)
    select
    when value = completed.receive
      received = value
    when timeout(1.second)
      raise "scheduler job was not processed"
    end

    received.should eq("run-1")
    sleep 50.milliseconds
    final = scheduler.status("wf")
    final.completed.should eq(1)
    final.running.should eq(0)
  end
end
