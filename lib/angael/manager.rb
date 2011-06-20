require 'angael/process_helper'
require 'logger'
module Angael
  # A Manager has a number of of worker objects. Starting the Manager simply
  # calls #start! on each worker, then it goes into an infinite loop, waiting
  # for SIGINT or SIGTERM. When either of those is received, the manager will
  # call #stop_with_wait on each Worker.
  class Manager
    LOOP_SLEEP_SECONDS = 1
    include ProcessHelper
    attr_reader :workers

    # Creates a new manager.
    #
    # @worker_class [Class] The class to use for the workers. Must respond
    #   to #new, #start!, and #stop_with_wait
    # @worker_count [Integer] The number of workers to manager. Default is 1.
    # @worker_args [Array] An array of arguments that will be passed to
    #   worker_class.new. The arguments will be splatted
    #   (i.e. `worker_class.new(*worker_args)`). Default is an empty Array, i.e.
    #   no arguments.
    # @opts [Hash] Additional options:
    #   :logger => A logger object, which should follow the Logger class in the
    #     standard library. Default nil, as in no logging.
    #   :restart_after => If set, 1 worker will be restarted after this number
    #     of seconds. If it is nil (the default), then workers will not get
    #     restarted for no reason. If your workers leak memory, this can help
    #     reduce the problem. A graceful restart is always attempted.
    def initialize(worker_class, worker_count=1, worker_args=[], opts={})
      @workers = []
      worker_count.times { workers << worker_class.new(*worker_args) }
      @restart_after = opts[:restart_after]
      # TODO: Add a spec for this
      raise ArgumentError, ':restart_after must be either an Integer greater than zero or nil' if @restart_after && (@restart_after.to_i != @restart_after || @restart_after == 0)
      @logger = opts[:logger]
    end


    # Starts workers by calling Worker#start! Loops forever waiting for SIGINT
    # or SIGTERM, at which time it calls Worker#stop_with_wait on each worker.
    def start!
      workers.each { |w| w.start! }

      trap("CHLD") do
        debug("SIGCHLD Received")
        @sigchld = true
      end
      trap("INT") do
        info("SIGINT Received")
        @interrupted = true
      end
      trap("TERM") do
        info("SIGTERM Received")
        @interrupted = true
      end

      if @restart_after
        loop do
          interrupted_handler
          sigchld_handler
          restart_worker_if_needed
          flush_logger
          sleep LOOP_SLEEP_SECONDS
        end
      else
        loop do
          interrupted_handler
          sigchld_handler
          flush_logger
          sleep LOOP_SLEEP_SECONDS
        end
      end
    end



    #########
    private #
    #########

    def stop!
      info("Attempting to gracefully stopping worker manager")
      # Tell each worker to stop, without waiting to see if it worked.
      workers.each { |w|
        debug("Calling #stop_without_wait for worker #{w.inspect}")
        w.stop_without_wait
        debug("Finished call to #stop_without_wait for worker #{w.inspect}")
      }
      # Wait for each worker to stop, one at a time.
      workers.each { |w|
        debug("Calling #stop_with_wait for worker #{w.inspect}")
        w.stop_with_wait
        debug("Finished call to #stop_with_wait for worker #{w.inspect}")
      }
      info("Exiting")
      exit 0
    end

    def log(level, msg)
      @logger.add(level, "#{Time.now.utc} - #{self.class} (pid #{$$}): #{msg}") if @logger
    end

    def debug(msg)
      log(Logger::DEBUG, msg)
    end

    def info(msg)
      log(Logger::INFO, msg)
    end


    def next_worker_to_restart
      @worker_count ||= workers.size
      @next_worker_to_restart_index ||= 0
      @next_worker_to_restart_index += 1
      @next_worker_to_restart_index %= @worker_count

      workers[@next_worker_to_restart_index]
    end


    def sigchld_handler
      if @sigchld
        workers.each do |w|
          result = exit_status(w.pid)
          if result
            # worker terminated
            # Restart it unless we asked it to stop.
            w.restart! unless w.stopping?
          end
        end
        @sigchld = false
      end
    end

    def interrupted_handler
      stop! if @interrupted
    end


    # Periodically restart workers, 1 at a time.
    def restart_worker_if_needed
      @seconds_until_restart_next_worker ||= @restart_after

      if @seconds_until_restart_next_worker > 0
        @seconds_until_restart_next_worker -= LOOP_SLEEP_SECONDS
      else
        w = next_worker_to_restart
        debug("Time to restart a worker: Calling #stop_with_wait for worker #{w.inspect}")
        w.stop_with_wait
        debug("Worker has been stopped: #{w.inspect}")
        w.start!
        debug("Worker has been restarted: #{w.inspect}")
        w = nil

        # Reset the counter
        @seconds_until_restart_next_worker = @restart_after
      end
    end

    def flush_logger
      @logger.flush if @logger && @logger.respond_to?(:flush)
    end
  end
end
