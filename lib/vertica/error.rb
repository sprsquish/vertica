# Main class for exceptions relating to Vertica.
class Vertica::Error < StandardError
  
  class ConnectionError < Vertica::Error; end
  class SSLNotSupported < ConnectionError; end
  class InterruptImpossible < Vertica::Error; end
  class MessageError < Vertica::Error; end
  class EmptyQueryError < Vertica::Error; end
  class TimedOutError < ConnectionError; end
    
  class SynchronizeError < Vertica::Error
    attr_reader :running_job, :requested_job

    def initialize(running_job, requested_job)
      @running_job, @requested_job = running_job, requested_job
      super("Cannot execute #{requested_job}, connection is in use for #{running_job}!")
    end
  end

  class QueryError < Vertica::Error
    
    attr_reader :error_response, :sql
    
    def initialize(error_response, sql)
      @error_response, @sql = error_response, sql
      super("#{error_response.error_message}, SQL: #{one_line_sql.inspect}" )
    end
    
    def one_line_sql
      @sql.gsub(/[\r\n]+/, ' ')
    end
    
    def self.from_error_response(error_response, sql)
      klass = QUERY_ERROR_CLASSES[error_response.sqlstate] || self
      klass.new(error_response, sql)
    end
  end
  
  QUERY_ERROR_CLASSES = {
    '55V03' => (LockFailure           = Class.new(Vertica::Error::QueryError)),
    '53000' => (InsufficientResources = Class.new(Vertica::Error::QueryError)),
    '53200' => (OutOfMemory           = Class.new(Vertica::Error::QueryError)),
    '42601' => (SyntaxError           = Class.new(Vertica::Error::QueryError)),
    '42V01' => (MissingRelation       = Class.new(Vertica::Error::QueryError)),
    '42703' => (MissingColumn         = Class.new(Vertica::Error::QueryError)),
    '22V04' => (CopyRejected          = Class.new(Vertica::Error::QueryError)),
    '42501' => (PermissionDenied      = Class.new(Vertica::Error::QueryError))
  }
end
