module Angael
  module TestSupport
    class SampleWorker
      include Angael::Worker
      def work
        # Do Nothing
      end
    end
  end
end
