require 'angael/process_helper'
module Angael
  # A Manager has a number of of worker objects. Starting the Manager simply
  # calls #start! on each worker, then it goes into an infinite loop, waiting
  # for SIGINT or SIGTERM. When either of those is received, the manager will
  # call #stop_with_wait on each Worker.
  class Manager
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
    #   :log_level => The log level, as defined by the Logger class in the
    #     standard library. One of:
    #       Logger::FATAL
    #       Logger::ERROR
    #       Logger::WARN
    #       Logger::INFO  # Default
    #       Logger::DEBUG
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
      if @logger
        @log_level = opts[:log_level] || begin
          require 'logger' # Only require it if it is absolutely neccessary.
          Logger::INFO
        end
      end
    end


    # Starts workers by calling Worker#start! Loops forever waiting for SIGINT
    # or SIGTERM, at which time it calls Worker#stop_with_wait on each worker.
    def start!
      workers.each { |w| w.start! }

      trap("CHLD") do
        workers.each do |w|
          result = exit_status(w.pid)
#print w.pid.to_s
#print "\t"
#p result
          if result
            # worker terminated
            # Restart it unless we asked it to stop.
            w.restart! unless w.stopping?
          end
        end
      end
      trap("INT") do
        log("SIGINT Received")
        @interrupted = true
      end
      trap("TERM") do
        log("SIGTERM Received")
        @interrupted = true
      end

      if @restart_after
        restart_after_counter = @restart_after
        loop do
          stop! if @interrupted

          # This ensures we are checking @interrupted every 1 second, but we
          # can set @restart_after to something greater than zero.
          if restart_after_counter > 0
            sleep 1
            restart_after_counter -= 1
          else
            # Periodically restart workers, 1 at a time.
            log("Sleeping for #@restart_after seconds")
            w = next_worker_to_restart
            log("Time to restart a worker: Calling #stop_with_wait for worker #{w.inspect}")
            w.stop_with_wait
            log("Worker has been stopped: #{w.inspect}")
            w.start!
            log("Worker has been restarted: #{w.inspect}")
            w = nil
            restart_after_counter = @restart_after
          end
        end
      else
        loop do
          stop! if @interrupted
          sleep 1
        end
      end
    end



    #########
    private #
    #########

    def stop!
      log("Attempting to gracefully stopping worker manager")
      # Tell each worker to stop, without waiting to see if it worked.
      workers.each { |w|
        log("Calling #stop_without_wait for worker #{w.inspect}")
        w.stop_without_wait
        log("Finished call to #stop_without_wait for worker #{w.inspect}")
      }
      # Wait for each worker to stop, one at a time.
      workers.each { |w|
        log("Calling #stop_with_wait for worker #{w.inspect}")
        w.stop_with_wait
        log("Finished call to #stop_with_wait for worker #{w.inspect}")
      }
      exit 0
    end

    def log(msg)
      @logger.add(@log_level, "#{Time.now.utc} - #{self.class} (pid #{$$}): #{msg}") if @logger
    end


    def next_worker_to_restart
      @worker_count ||= workers.size
      @next_worker_to_restart_index ||= 0
      @next_worker_to_restart_index += 1
      @next_worker_to_restart_index %= @worker_count

      workers[@next_worker_to_restart_index]
    end

  end
end
