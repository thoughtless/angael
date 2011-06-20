require 'angael/process_helper'
require 'logger'
module Angael
  # Usage
  #     include Angael::Worker
  #     def work
  #       # Do something interesting, without raising an exception.
  #     end
  # You can also add some optional behavior by defining the following methods:
  #    #after_fork  - This is run once, immediately after the child process is forked
  #    #before_exit - This is run once, immediately before the child process exits
  #    #fork_child  - This actually does the forking. You can overwrite this method
  #                   to do wrap the child process in a block. This is useful for
  #                   exception handling. Be sure to actually fork or you may break
  #                   something important.
  #    #log         - If defined, this will be called at various points of interest
  #                   with 1 String as the argument. Log levels are not supported.
  #    #timeout     - Number of seconds to wait for the child process to exit after
  #                   it is sent SIGINT. If you don't define this method, it waits
  #                   60 seconds.
  module Worker
    include ProcessHelper
    class ChildProcessNotStoppedError < StandardError; end

    attr_reader :pid

    # Loops forever, taking jobs off the queue. SIGINT will stop it after
    # allowing any jobs already taken from the queue to be processed.
    def start!
      @stopping = false

      @pid = fork_child do
        __info("Started")

        if respond_to?(:after_fork)
          __debug("Running after fork callback")
          after_fork
          __debug("Finished running after fork callback")
        end

        @interrupted = false
        trap("INT") do
          __info("SIGINT Received")
          @interrupted = true
        end
        trap("TERM") do
          __info("SIGTERM Received")
          @interrupted = true
        end

        loop do
          if @interrupted
            if respond_to?(:before_exit)
              __debug("Running before exit callback")
              before_exit
              __debug("Finished running before exit callback")
            end

            __info("Child process exiting gracefully")
            exit 0
          end
          work
        end
      end
    end

    # This only exists for the sake of testing. I need a way to stub the restart!
    # but not the original start!
    # Note: this method is not tested directly.
    # Users of this library should not call this method or depend on its existence
    # or behavior.
    def restart!
      start!
    end

    # Returns true if SIGINT was sent to the child process, even if the child
    # process does not exists.
    # Returns false if started? is true.
    # Sets stopping? to false.
    def stop_without_wait
      unless started?
        __warn("Tried to stop worker with PID #{pid} but it is not started")
        return false
      end

      # This informs the Manager (through #stopping?) that we intentionally
      # stopped the child process.
      @stopping = true

      __debug("Sending SIGINT to child process with pid #{pid}.")
      send_signal('INT', pid)
      true
    end

    # Keeps sending SIGINT until the child process exits. If #timeout seconds
    # pass, then it sends 1 SIGKILL. If that also fails, it raises ChildProcessNotStoppedError.
    def stop_with_wait
      return false unless stop_without_wait

      __debug("Waiting for child process with pid #{pid} to stop.")

      counter = 0

      while pid_running? && counter < timeout
        sleep 1
        counter += 1
        __info("Sending SIGINT to child process with pid #{pid}. Attempt Count: #{counter}.")
        send_signal('INT', pid)
      end

      if pid_running?
        __warn("Child process with pid #{pid} did not stop within #{timeout} seconds of SIGINT. Sending SIGKILL to child process.")
        send_signal('KILL', pid)
        sleep 1
      end

      if pid_running?
        # SIGKILL didn't work.
        msg = "Unable to kill child process with PID: #{pid}"
        __error(msg)
        raise ChildProcessNotStoppedError, msg
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


    def __log(level, msg)
      log(level, msg) if respond_to?(:log)
    end
    def __debug(msg)
      __log(Logger::DEBUG, msg)
    end
    def __info(msg)
      __log(Logger::INFO, msg)
    end
    def __warn(msg)
      __log(Logger::WARN, msg)
    end
    def __error(msg)
      __log(Logger::ERROR, msg)
    end

    # In seconds
    def timeout
      60
    end


    def pid_running?
      !exit_status(pid)
    end


    # This is the standard/default way of doing it. Overwrite this if you want
    # to wrap it in an exception handler, for example.
    def fork_child(&block)
      Process.fork &block
    end
  end
end
