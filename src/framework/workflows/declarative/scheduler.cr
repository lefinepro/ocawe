require "./types"
require "../../config/settings"
require "../../utils/time_compat"

module Ocawe
  module Workflow
    module Scheduler
      struct Job
        getter workflow_id : String
        getter run_id : String
        getter resource_id : String?
        getter input_data : AnyHash
        getter resources : AnyHash?

        def initialize(
          @workflow_id : String,
          @run_id : String,
          @resource_id : String? = nil,
          @input_data : AnyHash = {} of String => JSON::Any,
          @resources : AnyHash? = nil,
        )
        end
      end

      struct QueueStatus
        include JSON::Serializable

        getter workflow_id : String
        getter pending : Int32
        getter running : Int32
        getter workers : Int32
        getter completed : Int32
        getter failed : Int32

        def initialize(
          @workflow_id : String,
          @pending : Int32 = 0,
          @running : Int32 = 0,
          @workers : Int32 = 0,
          @completed : Int32 = 0,
          @failed : Int32 = 0,
        )
        end
      end

      class Manager
        def initialize(
          @settings : Ocawe::Config::SchedulerSettings,
          @runner : Proc(Job, Nil),
        )
          @queues = {} of String => WorkflowQueue
          @lock = Mutex.new
        end

        def enabled? : Bool
          @settings.enabled
        end

        def enqueue(job : Job) : QueueStatus
          queue_for(job.workflow_id).enqueue(job)
        end

        def status(workflow_id : String) : QueueStatus
          queue = @lock.synchronize { @queues[workflow_id]? }
          queue.try(&.status) || QueueStatus.new(workflow_id)
        end

        private def queue_for(workflow_id : String) : WorkflowQueue
          @lock.synchronize do
            @queues[workflow_id]? || begin
              queue = WorkflowQueue.new(workflow_id, @settings, @runner)
              @queues[workflow_id] = queue
              queue
            end
          end
        end
      end

      private class WorkflowQueue
        IDLE_POLL_MS = 50

        def initialize(
          @workflow_id : String,
          @settings : Ocawe::Config::SchedulerSettings,
          @runner : Proc(Job, Nil),
        )
          @pending = Deque(Job).new
          @running = 0
          @workers = 0
          @completed = 0
          @failed = 0
          @lock = Mutex.new
        end

        def enqueue(job : Job) : QueueStatus
          @lock.synchronize { @pending << job }
          ensure_worker_capacity
          status
        end

        def status : QueueStatus
          @lock.synchronize do
            QueueStatus.new(
              workflow_id: @workflow_id,
              pending: @pending.size,
              running: @running,
              workers: @workers,
              completed: @completed,
              failed: @failed,
            )
          end
        end

        private def ensure_worker_capacity : Nil
          loop do
            spawn_worker = false
            @lock.synchronize do
              total_load = @pending.size + @running
              desired = desired_workers(total_load)
              if @workers < desired
                @workers += 1
                spawn_worker = true
              end
            end
            break unless spawn_worker

            spawn { worker_loop }
            sleep @settings.scale_up_cooldown_ms.milliseconds if @settings.scale_up_cooldown_ms > 0
          end
        end

        private def desired_workers(total_load : Int32) : Int32
          return @settings.min_workers if total_load <= 0

          by_depth = (total_load.to_f / @settings.target_queue_depth).ceil.to_i
          desired = Math.max(@settings.min_workers, by_depth)
          Math.min(@settings.max_workers, desired)
        end

        private def worker_loop : Nil
          idle_since = nil.as(Ocawe::Utils::TimeCompat::Instant?)

          loop do
            job = nil.as(Job?)
            should_exit = false

            @lock.synchronize do
              if next_job = @pending.shift?
                job = next_job
                @running += 1
                idle_since = nil
              else
                idle_since ||= Ocawe::Utils::TimeCompat.monotonic
                if @workers > @settings.min_workers &&
                   Ocawe::Utils::TimeCompat.monotonic - idle_since.not_nil! >= @settings.scale_down_cooldown_ms.milliseconds
                  @workers -= 1
                  should_exit = true
                end
              end
            end

            return if should_exit

            if active_job = job
              begin
                @runner.call(active_job)
                @lock.synchronize { @completed += 1 }
              rescue ex
                STDERR.puts "[ocawecore] scheduler job failed: #{active_job.workflow_id}/#{active_job.run_id}: #{ex.message || ex.class.name}"
                @lock.synchronize { @failed += 1 }
              ensure
                @lock.synchronize { @running -= 1 }
                ensure_worker_capacity
              end
            else
              sleep IDLE_POLL_MS.milliseconds
            end
          end
        end
      end
    end
  end
end
