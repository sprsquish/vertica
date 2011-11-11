require 'socket'

class Vertica::Connection

  attr_reader :options, :notices, :transaction_status, :backend_pid, :backend_key, :parameters, :notice_handler

  attr_accessor :row_style, :debug

  def self.cancel(existing_conn)
    conn = self.new(existing_conn.options.merge(:skip_startup => true))
    conn.write Vertica::Messages::CancelRequest.new(existing_conn.backend_pid, existing_conn.backend_key)
    conn.write Vertica::Messages::Flush.new
    conn.socket.close
  end

  # Opens a connectio the a Vertica server
  # @param [Hash] options The connection options to use.
  def initialize(options = {})
    reset_values

    @options = {}
    options.each { |key, value| @options[key.to_s.to_sym] = value }
    @options[:port] ||= 5433

    @row_style = @options[:row_style] ? @options[:row_style] : :hash
    unless options[:skip_startup]
      startup_connection
      initialize_connection
    end
  end
  
  def on_notice(&block)
    @notice_handler = block
  end
  
  def socket
    @socket ||= begin
      raw_socket = TCPSocket.new(@options[:host], @options[:port].to_i)
      if @options[:ssl]
        require 'openssl'
        raw_socket.write Vertica::Messages::SslRequest.new.to_bytes
        if raw_socket.read(1) == 'S'
          raw_socket = OpenSSL::SSL::SSLSocket.new(raw_socket, OpenSSL::SSL::SSLContext.new)
          raw_socket.sync = true
          raw_socket.connect
        else
          raise Vertica::Error::ConnectionError.new("SSL requested but server doesn't support it.")
        end
      end
      
      raw_socket
    end
  end

  def ssl?
    socket.kind_of?(OpenSSL::SSL::SSLSocket)
  end

  def opened?
    @socket && @backend_pid && @transaction_status
  end

  def closed?
    !opened?
  end

  def write(message)
    raise ArgumentError, "invalid message: (#{message.inspect})" unless message.respond_to?(:to_bytes)
    puts "=> #{message.inspect}" if @debug
    socket.write message.to_bytes
  end

  def close
    write Vertica::Messages::Terminate.new
    socket.close
    @socket = nil
  rescue Errno::ENOTCONN # the backend closed the socket already
  ensure
    reset_values
  end

  def reset
    close if opened?
    reset_values
  end
  
  def read_message
    type = read_bytes(1)
    size = read_bytes(4).unpack('N').first
    raise Vertica::Error::MessageError.new("Bad message size: #{size}.") unless size >= 4
    message = Vertica::Messages::BackendMessage.factory type, read_bytes(size - 4)
    puts "<= #{message.inspect}" if @debug
    return message
  end
  
  def process_message(message)
    case message
    when Vertica::Messages::ErrorResponse
      raise Vertica::Error::ConnectionError.new(message.error_message)
    when Vertica::Messages::NoticeResponse
      @notice_handler.call(message) if @notice_handler
    when Vertica::Messages::BackendKeyData
      @backend_pid = message.pid
      @backend_key = message.key
    when Vertica::Messages::ParameterStatus
      @parameters[message.name] = message.value
    when Vertica::Messages::ReadyForQuery
      @transaction_status = message.transaction_status
    else
      raise Vertica::Error::MessageError, "Unhandled message: #{message.inspect}"
    end
  end
  

  def query(sql, options = {}, &block)
    job = Vertica::Query.new(self, sql, { :row_style => @row_style }.merge(options))
    job.row_handler = block if block_given?
    return job.run
  end
  
  def copy(sql, source = nil, &block)
    job = Vertica::Query.new(self, sql, :row_style => @row_style)
    if block_given?
      job.copy_handler = block 
    elsif source && File.exists?(source.to_s)
      job.copy_handler = lambda { |data| file_copy_handler(source, data) }
    elsif source.respond_to?(:read) && source.respond_to?(:eof?)
      job.copy_handler = lambda { |data| io_copy_handler(source, data) }
    end
    return job.run
  end

  def inspect
    safe_options = @options.reject{ |name, _| name == :password }
    "#<Vertica::Connection:#{object_id} @parameters=#{@parameters.inspect} @backend_pid=#{@backend_pid}, @backend_key=#{@backend_key}, @transaction_status=#{@transaction_status}, @socket=#{@socket}, @options=#{safe_options.inspect}, @row_style=#{@row_style}>"
  end
  
  protected
  
  def file_copy_handler(input_file, output)
    File.open(input_file, 'r') do |input|
      while data = input.read(4096)
        output << data
      end
    end
  end
  
  def io_copy_handler(input, output)
    until input.eof?
      output << input.read(4096) 
    end
  end

  def read_bytes(n)
    bytes = socket.read(n)
    raise Vertica::Error::ConnectionError.new("Couldn't read #{n} characters from socket.") if bytes.nil? || bytes.size != n
    return bytes
  end
  
  def startup_connection
    write Vertica::Messages::Startup.new(@options[:user], @options[:database])
    message = nil
    begin 
      case message = read_message
      when Vertica::Messages::Authentication
        if message.code != Vertica::Messages::Authentication::OK
          write Vertica::Messages::Password.new(@options[:password], message.code, {:user => @options[:user], :salt => message.salt})
        end
      else
        process_message(message)
      end
    end until message.kind_of?(Vertica::Messages::ReadyForQuery)
  end
  
  def initialize_connection
    query("SET SEARCH_PATH TO #{options[:search_path]}") if options[:search_path]
    query("SET ROLE #{options[:role]}") if options[:role]
  end

  def reset_values
    @parameters         = {}
    @backend_pid        = nil
    @backend_key        = nil
    @transaction_status = nil
    @socket             = nil
  end
end

require 'vertica/query'
require 'vertica/column'
require 'vertica/result'
require 'vertica/messages/message'
