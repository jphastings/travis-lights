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
    set :token, ENV['TRAVIS_USER_TOKEN']

    configure do |app|
      endpoint = "https://api.particle.io/v1/devices/#{ENV['SPARK_ID']}/traffic"
      headers = { 'Authorization' => "Bearer #{ENV['SPARK_AUTH']}"}
      http = Faraday.new(url: endpoint, headers: headers) do |http|
        http.request  :url_encoded
        http.adapter  Faraday.default_adapter
      end
      app.set :spark, http
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
      digest = Digest::SHA2.new.update("#{travis_payload.repository.owner_name}/#{travis_payload.repository.name}#{settings.token}")
      digest.to_s == env['HTTP_AUTHORIZATION']
    end

    def travis_payload
      @travis_payload ||= Hashie::Mash.new(JSON.load(params['payload']))
    end

    def change_lights(lights)
      settings.spark.post do |req|
        req.body = { 'params' => lights }
        req.options.timeout = 2
      end
    rescue Faraday::TimeoutError
      halt(504)
    end
  end
end