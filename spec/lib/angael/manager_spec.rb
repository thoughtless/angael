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
    subject { Angael::Manager.new(Angael::TestSupport::SampleWorker, 2) }
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


    %w(INT TERM).each do |sig|
      context "when it receives a SIG#{sig}" do
        it "should call #stop! on each Worker" do
          subject.workers.each do |w|
            w.stub(:start!) # We don't care about the sub-process, so don't start it.

            w.should_receive_in_child_process(:stop!)
          end

          pid = Process.fork do
            subject.start!
          end
          sleep 0.1 # Give the process a chance to start.
          Process.kill(sig, pid)
          sleep 0.1 # Give the TempFile a chance to flush

          # Clean up
          Process.wait(pid)
        end
      end
    end
  end
end
