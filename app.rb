# frozen_string_literal:true

require 'bundler/setup'
require 'json'
require 'redis'
require 'sinatra'

TYPES = %w[internet pmg17 lan].freeze
REDIS = Redis.new

class App < Sinatra::Application
  get '/' do
    locals = TYPES.each_with_object({}) do |type, hash|
      hash[type] = REDIS.hgetall(type).values.map! { JSON.parse _1 }
    end
    erb :index, locals: locals
  end

  post '/' do
    request.body.rewind
    data = request.body.read
    type, id = JSON.parse(data).values_at('type', 'id')
    return 422 if type.nil? || id.nil? || !TYPES.include?(type)

    REDIS.hset type, id, data
    201
  end
end
