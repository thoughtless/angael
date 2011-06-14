module Angael
  # A Manager has a number of of worker objects. Starting the Manager simply
  # calls #start! on each worker, then it goes into an infinite loop, waiting
  # for SIGINT or SIGTERM. When either of those is received, the manager will
  # call #stop! on each Worker.
  class Manager
    attr_reader :workers

    # Creates a new manager.
    #
    # @worker_class [Class] The class to use for the workers. Must respond
    #   to #new, #start!, and #stop!
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
      @logger = opts[:logger]
      if @logger
        @log_level = opts[:log_level] || begin
          require 'logger' # Only require it if it is absolutely neccessary.
          Logger::INFO
        end
      end
    end


    # Starts workers by calling Worker#start! Loops forever waiting for SIGINT
    # or SIGTERM, at which time it calls Worker#stop! on each worker.
    def start!
      workers.each { |w| w.start! }

      trap("CHLD") do
        workers.each do |w|
          result = wait(w.pid)
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
        stop!
      end
      trap("TERM") do
        stop!
      end

      if @restart_after
        loop do
          # Periodically restart workers, 1 at a time.
          sleep @restart_after
          w = next_worker_to_restart
          w.stop!
          w.start!
        end
      else
        loop do
          # Don't restart workers if nothing is wrong.
          sleep 1
        end
      end
    end



    #########
    private #
    #########

    def stop!
      log("SIGINT Received")
      workers.each { |w|
        log("Calling #stop! for worker #{w.inspect}")
        w.stop!
        log("Finished call to #stop! for worker #{w.inspect}")
      }
      exit 0
    end

    def log(msg)
      @logger.add(@log_level, "#{Time.now.utc} - #{self.class} (pid #{$$}): #{msg}") if @logger
    end

    # Returns immediately. If the process is still running, it returns nil.
    # If the process is a zombie, it returns an array with the pid as the
    # first element and a Process::Status object as the 2nd element, i.e.
    # it returns the same thing as Process.wait2. If the process does not
    # exist (i.e. it is completely gone) then it returns an array with the
    # pid as the first element and nil as the 2nd element (because there
    # is no Process::Status object to return).
    def wait(pid)
      begin
        Process.wait2(pid, Process::WNOHANG)
      rescue Errno::ECHILD
        [pid, nil] # It did exit, but we don't know the exit status.
      end
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
