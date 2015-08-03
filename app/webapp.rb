require_relative 'env'
require 'tilt/redcarpet'
require 'tilt/erb'
require 'sinatra/base'
require 'hashie/mash'
require 'digest/sha2'
require 'faraday'
require 'json'

module Traffic
  GREEN = 0b0001
  AMBER = 0b0010
  RED   = 0b0100

  class WebApp < Sinatra::Base
    set :markdown, layout_engine: :erb, fenced_code_blocks: true, with_toc_data: true, autolink: true
    set :root, File.join(__dir__, '..')

    configure do |app|
      enable :logging
      use Rack::CommonLogger
      app.set(:spark, Faraday.new { |http|
        http.request  :url_encoded
        http.adapter  Faraday.default_adapter
      })
    end

    get '/' do
      markdown File.read('README.md').gsub('public/', '')
    end

    post '/travis/:spark_id' do
      halt(401) unless from_travis?
      halt(406) unless travis_payload.branch == 'master'

      lights = case travis_payload.status_message
      when 'Passed', 'Fixed' then GREEN
      when 'Pending' then AMBER
      when 'Failing', 'Still Failing', 'Broken' then RED
      end

      change_lights(lights)
    end

    private

    def from_travis?
      digest = Digest::SHA2.new.update("#{repo_slug}#{travis_token}")
      (digest.to_s == env['HTTP_AUTHORIZATION']).tap do |is_valid|
        logger.warn "Given travis token is not correct: #{repo_owner}/#{env['HTTP_AUTHORIZATION']}" unless is_valid
      end
    end

    def travis_payload
      @travis_payload ||= Hashie::Mash.new(JSON.load(params['payload']))
    end

    def change_lights(lights)
      res = settings.spark.post do |req|
        req.url "https://api.particle.io/v1/devices/#{spark_id}/traffic"
        req.headers['Authorization'] = "Bearer #{spark_auth}"
        req.body = { 'params' => lights }
        req.options.timeout = 2
      end
      logger.info "Sent signal #{lights} to #{spark_id}"
    rescue Faraday::TimeoutError
      logger.info "Spark ID did not respond: #{spark_id}"
      halt(504)
    end

    def repo_slug
      "#{repo_owner}/#{repo_name}"
    end

    def repo_name
      travis_payload.repository.name
    end

    def repo_owner
      travis_payload.repository.owner_name
    end

    def spark_id
      params[:spark_id]
    end

    def travis_token
      ENV["travis.#{repo_owner}"].tap do |token|
        if token.nil?
          logger.warn "Travis owner not registered: #{repo_owner}"
          halt(404)
        end
      end
    end

    def spark_auth
      ENV["spark.#{spark_id}"].tap do |auth|
        if auth.nil?
          logger.warn "Spark ID not registered: #{spark_id}"
          halt(401)
        end
      end
    end
  end
end