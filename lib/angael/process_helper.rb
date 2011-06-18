module Angael
  module ProcessHelper
    # Returns immediately. If the process is still running, it returns nil.
    # If the process is a zombie, it returns an array with the pid as the
    # first element and a Process::Status object as the 2nd element, i.e.
    # it returns the same thing as Process.wait2. If the process does not
    # exist (i.e. it is completely gone) or it is not accessible to the
    # current process (i.e. an Errno::EPERM error is raised), then this method
    # returns an array with the pid as the first element and nil as the 2nd
    # element (because there is no Process::Status object to return).
    def exit_status(pid)
      # Sometimes wait2 returns nil even when the process has exited. This
      # raises an Errno::ESRCH error in that case.
      raise "Unexpected return value from Process.kill(0, pid)" unless Process.kill(0, pid) == 1

      Process.wait2(pid, Process::WNOHANG)
    rescue Errno::ECHILD, Errno::ESRCH, Errno::EPERM
      # There is no longer any record of this PID.
      # It did exit, but we don't know the exit status.
      [pid, nil]
    end


    # Will return nil instead of raising Errno::ESRCH when the process does
    # not exists.
    # TODO: Add explicit tests for this.
    def send_signal(signal, pid)
      Process.kill(signal, pid)
    rescue Errno::ESRCH
      nil
    end
  end
end
