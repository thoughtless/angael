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
    def initialize(worker_class, worker_count=1, worker_args=[], opts={})
      @workers = []
      worker_count.times { workers << worker_class.new(*worker_args) }
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

      loop do
        trap("INT") do
          stop!
        end
        trap("TERM") do
          stop!
        end
        sleep 1
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

  end
end
