require 'timeout'
module Angael
  # Usage
  #     include Angael::Worker
  #     def work
  #       # Do something interesting, without raising an exception.
  #     end
  # You can also add some optional behavior by defining the following methods:
  #    #after_fork - This is run once, immediately after the child process is forked
  #    #fork_child - This actually does the forking. You can overwrite this method
  #                  to do wrap the child process in a block. This is useful for
  #                  exception handling. Be sure to actually fork or you may break
  #                  something important.
  module Worker
    class ChildProcessNotStoppedError < StandardError; end

    attr_reader :pid

    # Options:
    #   :batch_timeout - After this number of seconds, other workers will be able
    #                    to work on the jobs reserved by #process_jobs.
    #   :batch_timeout_buffer - This is the number of seconds between when the
    #                           worker stops processing jobs and when other workers
    #                           can start processing the jobs that this worker had
    #                           resered. This should be set to the maximum length
    #                           of time a single job should take, plus the maximum
    #                           expected discrepancy between the system clocks on
    #                           all the worker servers.
    #   :logger => A logger object, which should follow the Logger class in the
    #     standard library. Default nil, as in no logging.
    #   :log_level => The log level, as defined by the Logger class in the
    #     standard library. One of:
    #       Logger::FATAL
    #       Logger::ERROR
    #       Logger::WARN
    #       Logger::INFO  # Default
    #       Logger::DEBUG
    def initialize(attrs={})
      @timeout = attrs[:timeout] || 60 # Seconds
      @batch_size = attrs[:batch_size] || 1
      @batch_timeout = attrs[:batch_timeout] || @batch_size * 5 # Seconds
      @batch_timeout_buffer = attrs[:batch_timeout_buffer] || 5 # Seconds
      @logger = attrs[:logger]
      if @logger
        @log_level = attrs[:log_level] || begin
          require 'logger' # Only require it if it is absolutely neccessary.
          Logger::INFO
        end
      end
    end


    # Loops forever, taking jobs off the queue. SIGINT will stop it after
    # allowing any jobs already taken from the queue to be processed.
    def start!
      trap("CHLD") do
        log("trapped SIGCHLD. Child PID #{pid}.")

        # @stopping is set by #stop!. If it is true, then the child process was
        # expected to die. If it is false/nil, then this is unexpected.
        log("Child process died unexpectedly") unless @stopping
        # Reap the child process so that #started? will return false. But we can't
        # block because this may be called for a Worker when a different Worker's
        # child is the process that died.
        wait_for_child(:dont_block => true) if pid
      end

      @pid = fork_child do
        log("Started")

        if respond_to?(:after_fork)
          log("Running after fork callback")
          after_fork
          log("Finished running after fork callback")
        end

        @interrupted = false
        trap("INT") do
          log("SIGINT Received")
          @interrupted = true
        end
        trap("TERM") do
          log("SIGTERM Received")
          @interrupted = true
        end

        loop do
          if @interrupted
            log("Child process exiting gracefully")
            exit 0
          end
          work
        end
      end
    end

    def stop!
      unless started?
        log("Called stop for worker with PID #{pid} but it is not started")
        return false
      end

      # Some internal state so that other parts of our code know that we
      # intentionally stopped the child process.
      @stopping = true

      begin
        log("Sending SIGINT to child process with pid #{pid}.")
        Timeout::timeout(@timeout) do
          Process.kill('INT', pid)
          wait_for_child
        end
      rescue Timeout::Error
        begin
          log("Child process with pid #{pid} did not stop with #@timeout seconds of SIGINT. Sending SIGKILL to child process.")
          # This only leaves 1 second for the SIGKILL to take effect. I don't
          # know if that is enough time (or maybe too much time).
          Timeout::timeout(1) do
            Process.kill('KILL', pid)
            wait_for_child
          end
        rescue Timeout::Error
          if pid_running?
            msg = "Unable to kill child process with PID: #{pid}"
            log(msg)
            raise ChildProcessNotStoppedError, msg
          end
        end
      end
      @stopping = false
    end

    def started?
      !!(pid && pid_running?)
    end
    def stopped?
      !started?
    end

    #########
    private #
    #########


    # The worker will call this method over and over in a loop.
    def work
      raise "implement this in a class that includes this module"
    end


    def log(msg)
      @logger.add(@log_level, "#{Time.now.utc} - #{self.class} (pid #{$$}): #{msg}") if @logger
    end


    # Note: if the pid is running, but this process doesn't have permissions to
    #       access it, then this will return false.
    def pid_running?
      begin
        Process.kill(0, pid) == 1
      rescue Errno::ESRCH, Errno::EPERM
        false
      end
    end

    # Will just return if the child process is not running.
    def wait_for_child(opts={})
      begin
        log("Waiting for child with pid #{pid}.")
        if opts[:dont_block]
          # When this is called as the result of a SIGCHLD
          # we need to pass in Process::WNOHANG as the 2nd argument, otherwise when
          # there are multiple workers, some workers will trap SIGCHLD when other
          # workers' child processes die. Without this argument, those workers will
          # hang forever, which also hangs the worker manager.
          Process.wait(pid, Process::WNOHANG)
        else
          Process.wait(pid)
        end
      rescue Errno::ECHILD
        # The child process has already been reaped.
      end
    end

    # This is the standard/default way of doing it. Overwrite this if you want
    # to wrap it in an exception handler, for example.
    def fork_child(&block)
      Process.fork &block
    end
  end
end
