require 'spec_helper'

describe Angael::ProcessHelper do
  include Angael::ProcessHelper

  describe "exit_status" do
    context "when Process.kill raises Errno::ESRCH" do
      before { Process.stub(:kill) { raise Errno::ESRCH } }
      it "should return an array of [pid, nil]" do
        exit_status(123456).should == [123456, nil]
      end
    end

    context "when Process.kill return 1" do
      before { Process.stub(:kill).and_return(1) }

      context "when Process.wait2 raises Errno::ECHILD" do
        before { Process.stub(:wait2) { raise Errno::ECHILD } }
        it "should return an array of [pid, nil]" do
          exit_status(123456).should == [123456, nil]
        end
      end

      context "when Process.wait2 returns nil" do
        before { Process.stub(:wait2).and_return(nil) }
        it "should return nil" do
          exit_status(123456).should be_nil
        end
      end

      context "when Process.wait2 returns an array of [pid, exitstatus]" do
        before do
          @exitstatus = mock(Process::Status)
          Process.stub(:wait2).and_return([123456, @exitstatus])
        end
        it "should return an array of [pid, exitstatus]" do
          exit_status(123456).should == [123456, @exitstatus]
        end
      end
    end
  end


  describe "send_signal" do
    it "should call kill" do
      pid = 123456
      sig = 'INT'
      Process.should_receive(:kill).with(sig, pid)
      send_signal(sig, pid)
    end

    context "when Process.kill raises Errno::ESRCH" do
      it "should return nil" do
        Process.stub(:kill) { raise Errno::ESRCH }
        send_signal('INT', 123456).should be_nil
      end
    end
  end
end
