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
  #    #log        - If defined, this will be called at various points of interest
  #                  with 1 String as the argument. Log levels are not supported.
  #    #timeout    - Number of seconds to wait for the child process to exit after
  #                  it is sent SIGINT. If you don't define this method, it waits
  #                  60 seconds.
  module Worker
    class ChildProcessNotStoppedError < StandardError; end

    attr_reader :pid

    # Loops forever, taking jobs off the queue. SIGINT will stop it after
    # allowing any jobs already taken from the queue to be processed.
    def start!
      @stopping = false

      @pid = fork_child do
        __log("Started")

        if respond_to?(:after_fork)
          __log("Running after fork callback")
          after_fork
          __log("Finished running after fork callback")
        end

        @interrupted = false
        trap("INT") do
          __log("SIGINT Received")
          @interrupted = true
        end
        trap("TERM") do
          __log("SIGTERM Received")
          @interrupted = true
        end

        loop do
          if @interrupted
            __log("Child process exiting gracefully")
            exit 0
          end
          work
        end
      end
    end

    def stop!
      unless started?
        __log("Called stop for worker with PID #{pid} but it is not started")
        return false
      end

      # This informs the Manager (through #stopping?) that we intentionally
      # stopped the child process.
      @stopping = true

      begin
        __log("Sending SIGINT to child process with pid #{pid}.")
        Timeout::timeout(timeout) do
          Process.kill('INT', pid)
          wait_for_child
        end
      rescue Timeout::Error
        begin
          __log("Child process with pid #{pid} did not stop within #{timeout} seconds of SIGINT. Sending SIGKILL to child process.")
          # This only leaves 1 second for the SIGKILL to take effect. I don't
          # know if that is enough time (or maybe too much time).
          Timeout::timeout(1) do
            Process.kill('KILL', pid)
            wait_for_child
          end
        rescue Timeout::Error
          if pid_running?
            msg = "Unable to kill child process with PID: #{pid}"
            __log(msg)
            raise ChildProcessNotStoppedError, msg
          end
        end
      end
    end

    def started?
      !!(pid && pid_running?)
    end
    def stopped?
      !started?
    end
    # TODO: test this
    def stopping?
      @stopping
    end

    #########
    private #
    #########


    # The worker will call this method over and over in a loop.
    def work
      raise "implement this in a class that includes this module"
    end


    def __log(msg)
      log(msg) if respond_to?(:log)
    end


    # In seconds
    def timeout
      60
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
        __log("Waiting for child with pid #{pid}.")
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
