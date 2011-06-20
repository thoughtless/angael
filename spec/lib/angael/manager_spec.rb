require 'spec_helper'

describe Angael::Manager do
  describe ".new" do
    subject { Angael::Manager.new(Angael::TestSupport::SampleWorker, 2) }
    it "should have 2 workers when 2 is passed in to the initializer" do
      should have(2).workers
    end

    it "should call new on the passed in job class" do
      Angael::TestSupport::SampleWorker.should_receive(:new).exactly(2).times
      Angael::Manager.new(Angael::TestSupport::SampleWorker, 2)
    end

    it "should call new on the passed in job class with the passed in arguments" do
      args = [1, 2, 3]
      Angael::TestSupport::SampleWorker.should_receive(:new).with(*args).exactly(2).times
      Angael::Manager.new(Angael::TestSupport::SampleWorker, 2, args)
    end
  end

  describe "#start!" do
    subject { Angael::Manager.new(Angael::TestSupport::SampleWorker, 3) }

    it "should start all its workers" do
      subject.workers.each do |w|
        w.should_receive_in_child_process(:start!)
      end

      pid = Process.fork do
        subject.start!
      end

      # Need to sleep to allow time for temp files used by should_receive_in_child_process to flush
      sleep 0.1

      # Clean up
      Process.kill('KILL', pid)
      Process.wait(pid)
    end

    context "when :restart_after is set to 0.5" do
      after do
        clean_up_pid(@pid)
      end

      subject { Angael::Manager.new(Angael::TestSupport::SampleWorker, 3, [], :restart_after => 0.5) }

      it "should restart workers 1 at a time, at 0.5 second intervals" do
        subject.workers.each do |w|
          # This isn't used for restarts.
          w.stub(:stop_without_wait)
        end

        subject.workers[0].should_receive_in_child_process(:stop_with_wait).exactly(1).times
        subject.workers[1].should_receive_in_child_process(:stop_with_wait).at_least(:once)#.exactly(2).times # This is the worker that got restarted.
        subject.workers[2].should_receive_in_child_process(:stop_with_wait).exactly(1).times

        subject.workers[0].should_receive_in_child_process(:start!).exactly(1).times
        subject.workers[1].should_receive_in_child_process(:start!).at_least(:once)#.exactly(2).times # This is the worker that got restarted.
        subject.workers[2].should_receive_in_child_process(:start!).exactly(1).times


        # As an alternative to should_receive_in_child_process, we
        # fork a process which will send SIGINT to this current process.
        # Then we start the Manager in this process and wait for it to
        # get the SIGINT. Finally we rescue SystemExit so that this
        # process doesn't exit with the Manager stops.
        # TODO: Be consistent in my use of this technique vs. should_receive_in_child_process.
#        current_pid = $$
#        @pid = Process.fork do
#          sleep 5#0.6 # Add a 0.1 second buffer to the value of :restart_after to give the process a chance to start.
#          Process.kill('INT', current_pid)
#          exit 0
#        end
#        begin
#          puts "about to call subject.start!"
#          subject.start!
#          puts "call to subject.start! just finished"
#        rescue SystemExit
#          nil
#        end
#
#        sleep 5


        @pid = Process.fork do
          subject.start!
        end

        sleep 0.6 # Add a 0.1 second buffer to the value of :restart_after to give the process a chance to start.
        Process.kill('INT', @pid)

      end
    end

    context "when it receives a SIGCHLD" do
      after(:each) do
        clean_up_pid(@pid)
      end

      context "when worker was asked to stop" do
#        it "should not restart the child process" do
#          subject.workers.each do |w|
#            w.stub(:work).and_return { sleep 0.1 }
#            w.should_receive_in_child_process(:restart!).exactly(0).times
#          end
#
#          @pid = Process.fork do
#            subject.start!
#          end
#
#          sleep 0.1 # Give the process a chance to start.
#          # This sends stop_with_wait to all the workers.
#          Process.kill('INT', @pid)
#          sleep 0.1 # Give the TempFile a chance to flush
#        end
#
#        it "should reap the child processes" do
#          subject.workers.each do |w|
#            w.stub(:work).and_return { sleep 0.05 }
#          end
#
#          # We need access to the worker objects to get their PIDs, so we
#          # fork a process which will send SIGINT to this current process.
#          # Then we start the Manager in this process and wait for it to
#          # get the SIGINT. Finally we rescue SystemExit so that this
#          # process doesn't exit with the Manager stops.
#          current_pid = $$
#          @pid = Process.fork do
#            sleep 0.1 # Give the process a chance to start.
#            Process.kill('INT', current_pid)
#            exit 0
#          end
#          begin
#            subject.start!
#          rescue SystemExit
#            nil
#          end
#
#          subject.workers.each do |w|
#            lambda do
#              Process.kill(0, w.pid)
#            end.should raise_error(Errno::ESRCH, "No such process")
#          end
#        end
      end

      context "when worker was not asked to stop" do
        after(:each) do
          # Clean up
          Process.kill('INT', @pid)
          sleep 0.1
        end
#        it "should restart the child process" do
#          subject.workers.each do |w|
#            w.stub(:work).and_return do
#              sleep 0.05
#              # This is like exiting with an exception, but it prevents the ugly
#              # stacktrace.
#              exit 1
#            end
#            w.should_receive_in_child_process(:restart!).at_least(1).times
#          end
#
#          @pid = Process.fork do
#            subject.start!
#          end
#
#          sleep 0.1 # Give the process a chance to start.
#        end
      end
    end

    %w(INT TERM).each do |sig|
      context "when it receives a SIG#{sig}" do
#        it "should call #stop_without_wait on each Worker" do
#          subject.workers.each do |w|
#            w.stub(:start!) # We don't care about the sub-process, so don't start it.
#
#            w.should_receive_in_child_process(:stop_without_wait).at_least(1).times
#          end
#
#          pid = Process.fork do
#            subject.start!
#          end
#          sleep 0.1 # Give the process a chance to start.
#          Process.kill(sig, pid)
#          sleep 0.1 # Give the TempFile a chance to flush
#
#          # Clean up
#          Process.wait(pid)
#        end
#
#        it "should call #stop_with_wait on each Worker" do
#          subject.workers.each do |w|
#            w.stub(:start!) # We don't care about the sub-process, so don't start it.
#
#            w.should_receive_in_child_process(:stop_with_wait)
#          end
#
#          pid = Process.fork do
#            subject.start!
#          end
#          sleep 0.1 # Give the process a chance to start.
#          Process.kill(sig, pid)
#          sleep 0.1 # Give the TempFile a chance to flush
#
#          # Clean up
#          Process.wait(pid)
#        end
      end
    end
  end

  def clean_up_pid(pid)
    unless Process.wait2(pid, Process::WNOHANG)
      Process.kill('KILL', pid) unless
      Process.wait(pid) rescue nil
    end
  end
end
