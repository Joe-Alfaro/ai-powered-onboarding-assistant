module Health
  module Probes
    # Runs `tesseract --version` from PATH. Down when it isn't found, exits non-zero or doesn't
    # finish within the timeout, in which case it is killed.
    class Ocr
      POLL_SECONDS = 0.05

      def initialize(timeout:)
        @timeout = timeout
      end

      def call
        pid = Process.spawn("tesseract", "--version", in: File::NULL, out: File::NULL, err: File::NULL, pgroup: true)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @timeout
        loop do
          _, status = Process.waitpid2(pid, Process::WNOHANG)
          return status.success? if status
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep POLL_SECONDS
        end
        stop(pid)
        false
      end

      private

      def stop(pid)
        Process.kill("KILL", -pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end
