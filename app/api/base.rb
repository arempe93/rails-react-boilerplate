# frozen_string_literal: true

# load extra helpers that aren't autoloaded
%w[validators].each do |dir|
  Dir[File.dirname(__FILE__) + "/#{dir}/*.rb"].each { |file| require file }
end

module API
  class Base < Grape::API
    use Grape::Middleware::Globals
    use Middleware::RequestId
    insert_after Grape::Middleware::Formatter,
                 Middleware::Logger

    format :json

    helpers Support::Errors
    helpers Support::Helpers

    rescue_from Grape::Exceptions::ValidationErrors do |e|
      bad_request!(message: 'Bad Request', errors: e.full_messages)
    end

    rescue_from(:all) do |e|
      server_error!(message: e.message, source: e.backtrace.first)
    end

    mount Example

    add_swagger_documentation hide_format: true

    route %i[get post put patch delete], '*path' do
      not_found! 'API endpoint does not exist'
    end
  end
end
