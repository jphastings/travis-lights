require_relative 'env'
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
    configure do |app|
      app.set(:spark, Faraday.new { |http|
        http.request  :url_encoded
        http.adapter  Faraday.default_adapter
      })
    end

    post '/travis' do
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
      digest.to_s == env['HTTP_AUTHORIZATION']
    end

    def travis_payload
      @travis_payload ||= Hashie::Mash.new(JSON.load(params['payload']))
    end

    def change_lights(lights)
      settings.spark.post do |req|
        req.url = "https://api.particle.io/v1/devices/#{spark_id}/traffic"
        req.headers = { 'Authorization' => "Bearer #{spark_auth}"}
        req.body = { 'params' => lights }
        req.options.timeout = 2
      end
    rescue Faraday::TimeoutError
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
      request.query_string
    end

    def travis_token
      ENV["travis.#{repo_owner}"].tap do |token|
        halt(404) if token.nil?
      end
    end

    def spark_auth
      ENV["spark.#{spark_id}"].tap do |auth|
        halt(401) if auth.nil?
      end
    end
  end
end