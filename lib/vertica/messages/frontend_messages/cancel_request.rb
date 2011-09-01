module Vertica
  module Messages
    class CancelRequest < FrontendMessage
      message_id nil

      def initialize(backend_pid, backend_key)
        @backend_pid = backend_pid
        @backend_key = backend_key
      end

      def to_bytes
        message_string [80877102, @backend_pid, @backend_key].pack('N3')
      end

    end
  end
end
