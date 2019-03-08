# frozen_string_literal: true

module Database
  DB_RUNTIME_KEY = :grape_db_runtime

  def db_runtime=(value)
    RequestStore.store[DB_RUNTIME_KEY] = value
  end

  def db_runtime
    RequestStore.store[DB_RUNTIME_KEY] ||= 0
  end

  def reset_db_runtime
    self.db_runtime = 0
  end

  def append_db_runtime(event)
    self.db_runtime += event.duration
  end

  def total_db_runtime
    db_runtime.round(2)
  end
end

module Middleware
  class Logger < Grape::Middleware::Globals
    include Database
    include ANSIColor
    include ErrorHandling

    SLASH = '/'

    GRAPE_PARAMS = Grape::Env::GRAPE_REQUEST_PARAMS
    RACK_REQUEST_BODY = Grape::Env::RACK_REQUEST_FORM_HASH
    ACTION_DISPATCH_PARAMS = 'action_dispatch.request.request_parameters'

    attr_reader :logger

    def initialize(app, headers: nil, **options)
      @app = app

      @options = options
      @logger = Rails.application.config.logger
      @filter = ActionDispatch::Http::ParameterFilter.new(Rails.application.config.filter_parameters)
      @display_headers = headers

      ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
        event = ActiveSupport::Notifications::Event.new(*args)
        append_db_runtime(event)
      end
    end

    def call!(env)
      @env = env

      if logger.respond_to?(:tagged)
        request_id = RequestStore.store[:request_id]
        logger.tagged(cyan(request_id)) { perform }
      else
        perform
      end
    end

    private

    def perform
      start_timings
      log_request

      response = call_with_error_handling do |error|
        log_failure(error)
      end

      response.tap do |(status, headers, _body)|
        log_response(status, headers)
      end
    end

    def log_request
      request = env[Grape::Env::GRAPE_REQUEST]
      method = request.request_method

      logger.info ''
      logger.info format("Started %<method>s '%<path>s'", method: green(method, bold: true),
                                                          path: cyan(request.path))
      logger.info "Processing by #{red(processed_by, bold: true)}"
      logger.info "  Parameters: #{yellow(parameters)}"
      logger.info "  Headers: #{yellow(print_display_headers)}" if @display_headers
    end

    def log_response(status, headers = {})
      headers['X-Runtime'] = total_runtime
      headers['X-DB-Runtime'] = total_db_runtime

      logger.info green("Completed #{status}: total=#{total_runtime}ms - db=#{total_db_runtime}ms")
      logger.info ''
    end

    def log_failure(error)
      message = error[:message]&.fetch(:message, error[:message].to_s)
      message ||= '<NO RESPONSE>'

      logger.info magenta("  ! Failing with #{error[:status]} (#{message})")

      error[:headers] ||= {}
      log_response(error[:status], error[:headers])
    end

    def parameters
      request_params = env[GRAPE_PARAMS].to_hash
      request_params.merge!(env[RACK_REQUEST_BODY]) if env[RACK_REQUEST_BODY]
      request_params.merge!(env[ACTION_DISPATCH_PARAMS]) if env[ACTION_DISPATCH_PARAMS]

      @filter.filter(request_params)
    end

    def filtered_headers
      return request_headers if @display_headers == :all

      Array(@display_headers).each_with_object({}) do |name, acc|
        normalized_name = name.titlecase.tr(' ', '-') # X-Sample-header-NAME => X-Sample-Header-Name
        header_value = request_headers.fetch(normalized_name, nil)

        acc[normalized_name.to_sym] = header_value if header_value
      end
    end

    def request_headers
      @request_headers ||= env[Grape::Env::GRAPE_REQUEST_HEADERS].to_hash
    end

    def start_timings
      @runtime_start = Time.now
      reset_db_runtime
    end

    def total_runtime
      ((Time.now - @runtime_start) * 1_000).round(2)
    end

    def processed_by
      endpoint = env[Grape::Env::API_ENDPOINT]

      result = []
      result << (endpoint.namespace == SLASH ? '' : endpoint.namespace)

      result.concat(endpoint.options[:path].map { |path| path.to_s.sub(SLASH, '') })
      endpoint.options[:for].to_s << result.join(SLASH)
    end
  end
end
