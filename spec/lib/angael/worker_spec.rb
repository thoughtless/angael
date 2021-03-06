require 'spec_helper'
require 'tempfile'


describe Angael::Worker do
  subject { Angael::TestSupport::SampleWorker.new }

  describe "#start!" do
    before { subject.stub(:work => nil) }
    after { subject.stop_with_wait if subject.started? }

    it "should set #pid" do
      subject.pid.should be_nil
      subject.start!
      subject.pid.should_not be_nil
    end

    it "should create a process that has the pid of #pid" do
      subject.start!
      pid_running?(subject.pid).should be_true
    end

    it "should be started" do
      subject.should_not be_started
      subject.start!
      subject.should be_started
    end

    it "should not be stopping" do
      subject.start!
      subject.should_not be_stopping
    end

    it "should be doing work" do
      # TODO: Update #should_receive_in_child_process to allow for a
      #       #more_than_once option, then use that instead of setting this all
      #       up manually.

      # I'm using this temp file to ensure we are actually doing something. I
      # can't just use should_receive because the "work" is done in a different
      # process.
      file = Tempfile.new('work-stub')
      subject.stub(:work) do
        @work_counter ||= 1
        msg = "I am working. My PID is #{$$}. Run number #@work_counter"
        file.puts msg
      end

      subject.start!

      # Check that work was done (i.e. there is something in the file).
      sleep 0.1
      file.rewind
      lines = file.readlines.size
      lines.should > 0

      # Check that more work was done (i.e. there is more in the file than
      # last time we checked).
      old_lines = lines
      sleep 0.3
      file.rewind
      lines = file.readlines.size
      lines.should > old_lines
    end

    context "child process dies unexpectedly" do
      before { subject.start! }
      it "should not be started" do
        Process.kill('KILL', subject.pid)
        sleep 0.1 # Wait for SIGKILL to take effect.
        # We must clean up the zombies here because the Worker class noramlly
        # relies on the worker manager to do that.
        Process.wait2(subject.pid, Process::WNOHANG)
        subject.should_not be_started
      end

      it "should still have #pid set to the child process's pid" do
        pid = subject.pid
        Process.kill('KILL', subject.pid)
        subject.pid.should == pid
      end
    end

  end



  describe "#stop_without_wait" do
    before { subject.stub(:work => nil) }
    after { subject.stop_with_wait }

    context "when stopped" do
      it "should return false" do
        subject.should_not be_started
        subject.stop_without_wait.should be_false
      end

      it "should not be stopping" do
        subject.stop_without_wait
        subject.should_not be_stopping
      end

      it "should not send a SIGINT to the child process" do
        should_not_receive_and_run(Process, :kill, 'INT', subject.pid)
        subject.stop_without_wait
      end

      it "should return false" do
        subject.stop_without_wait.should be_false
      end
    end

    context "when started" do
      before { subject.start! }
      it "should send a SIGINT to the child process" do
        should_receive_and_run(Process, :kill, 'INT', subject.pid)
        subject.stop_without_wait
      end

      it "should be stopping" do
        subject.stop_without_wait
        subject.should be_stopping
      end

      it "should return true" do
        subject.stop_without_wait.should be_true
      end
    end
  end


  describe "#stop_with_wait" do
    before { subject.stub(:work => nil) }
    after { subject.stop_with_wait }

    context "when stopped" do
      it "should return false" do
        subject.should_not be_started
        subject.stop_with_wait.should be_false
      end

      it "should not be stopping" do
        subject.stop_with_wait
        subject.should_not be_stopping
      end

      it "should not send a SIGINT to the child process" do
        should_not_receive_and_run(Process, :kill, 'INT', subject.pid)
        subject.stop_with_wait
      end
    end

    context "when started" do
      it "should send a SIGINT to the child process" do
        subject.start!
        should_receive_and_run(Process, :kill, 'INT', subject.pid)
        subject.stop_with_wait
      end

      it "should be stopping" do
        subject.start!
        subject.stop_with_wait
        subject.should be_stopping
      end

      context "when child process does die within the worker's timeout" do
        subject do
          worker = Angael::TestSupport::SampleWorker.new
          worker.stub(:timeout => 2)
          worker
        end
        before do
          subject.stub(:work) { nil }
          subject.start!
        end
        it "should be stopped" do
          subject.stop_with_wait
          subject.should be_stopped
        end

        it "should not have a child process with the pid #pid" do
          subject.stop_with_wait
          pid_running?(subject.pid).should be_false
        end

        it "should not send a SIGKILL to the child process" do
          should_not_receive_and_run(Process, :kill, 'KILL', subject.pid)
          subject.stop_with_wait
        end

        it "should have the (now dead) child process' PID as #pid" do
          pid = subject.pid
          subject.stop_with_wait
          subject.pid.should == pid
        end
      end

      context "when child process does not die within the worker's timeout" do
        subject do
          worker = Angael::TestSupport::SampleWorker.new
          worker.stub(:timeout => 1)
          worker
        end
        before do
          subject.stub(:work) { sleep 1000 }
          subject.start!
          sleep 1 # Leave some time for the child process to enter the sleep.
        end

        it "should be stopped" do
          subject.stop_with_wait
          subject.should be_stopped
        end

        it "should not have a child process with the pid #pid" do
          subject.stop_with_wait
          pid_running?(subject.pid).should be_false
        end

        it "should send a SIGKILL to the child process" do
          should_receive_and_run(Process, :kill, 'KILL', subject.pid)
          subject.stop_with_wait
        end

        context "child process does not die after receiving SIGKILL" do
          before do
            Process.instance_eval { alias :_original_kill :kill }
            # This ensures that SIGKILL doesn't kill the child process, but
            # all other signals are processed.
            Process.stub(:kill) do |*args|
              if args == ['KILL', subject.pid]
                nil
              else
                Process._original_kill(*args)
              end
            end
          end
          after do
            # Clean up
            Process._original_kill('KILL', subject.pid)
            sleep 0.1 # Wait for SIGKILL to take effect.
            # We must clean up the zombies here because the Worker class noramlly
            # relies on the worker manager to do that.
            Process.wait2(subject.pid, Process::WNOHANG)
            pid_running?(subject.pid).should be_false
          end

          it "should raise an error with the child process' pid in the message" do
            pid_running?(subject.pid).should be_true
            lambda do
              subject.stop_with_wait
            end.should raise_error(Angael::Worker::ChildProcessNotStoppedError, /#{subject.pid}/)

            # Confirm the PID is still running
            pid_running?(subject.pid).should be_true
          end
        end
      end
    end
  end


  # Note: Be very careful when trying to refactor these tests. The exact timing
  #       of signals is not very easy to predict. The specs in this describe
  #       block have been carefully tested (with many test runs) to make sure
  #       they are very unlikely to fail for random timing reasons. If you must
  #       change these specs, make sure you run the whole test suite several
  #       times to make sure all the specs consistently pass.
  describe "child process handling of signals" do
    context "when started" do
      before { subject.stub(:work) }

      %w(INT TERM).each do |sig|
        context "when child process receives SIG#{sig}" do
          it "should exit gracefully (i.e. with status 0)" do
            subject.start!
            # Don't let the worker reap its child process because we need to
            # get at the PID and status here.
            subject.stub(:wait_for_child)
            sleep 0.1 # Make sure there was enough time for the child process to start.
            Process.kill(sig, subject.pid)
            pid, status = Process.wait2(subject.pid)
            status.should == 0
          end
        end
      end
    end
  end



  ###########
  # Helpers #
  ###########

  # Note: if the pid is running, but this process doesn't have permissions to
  #       access it, then this will return false.
  def pid_running?(pid)
    begin
      Process.kill(0, pid) == 1
    rescue Errno::ESRCH, Errno::EPERM
      false
    end
  end

  # These methods let me set an expectation that amethod should be called, but
  # also allow that method to actually be called.
  def stub_and_run(object, method, *args)
    unstubbed_method = "_unstubbed_#{method}".to_sym
    method = method.to_sym
    # This is a bit ugly, but because alias is not a method, but a keyword, we
    # need to use eval like this. For more details see this thread:
    #    http://www.ruby-forum.com/topic/135598
    object.instance_eval "alias #{unstubbed_method.inspect} #{method.inspect}"
    object.stub(method) { |*args| object.send(unstubbed_method, *args) }
  end
  def should_receive_and_run(object, method, *args)
    stub_and_run(object, method, *args)
    object.should_receive(method).with(*args)
  end
  def should_not_receive_and_run(object, method, *args)
    stub_and_run(object, method, *args)
    object.should_not_receive(method).with(*args)
  end
end
