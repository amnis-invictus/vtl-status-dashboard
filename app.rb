# frozen_string_literal:true

require 'base64'
require 'bundler/setup'
require 'json'
require 'redis'
require 'sinatra'
require 'openssl'

TYPES = %w[internet pmg17 lan].freeze
CIPHER = 'AES-256-CBC'
MAGIC = 'Salted__'
SALT_SIZE = 8
KEY_SIZE = 32
IV_SIZE = 16
REDIS = Redis.new url: ENV['REDIS_URL']
POST_SECRET = ENV['POST_SECRET']


class App < Sinatra::Application
  get '/' do
    locals = TYPES.each_with_object({}) do |type, hash|
      hash[type] = REDIS.hgetall(type).values.map! { JSON.parse _1 }
    end
    erb :index, locals: locals
  end

  post '/' do
    request.body.rewind
    raw_data = request.body.read

    enc_data_base64 = JSON.parse(raw_data)['data']
    return 422 if enc_data_base64.nil?

    enc_data = Base64.decode64(enc_data_base64)

    return 422 unless MAGIC == enc_data[0..(MAGIC.size - 1)]

    salt = enc_data[MAGIC.size..(MAGIC.size + SALT_SIZE.size - 1)]
    data = enc_data[(MAGIC.size + SALT_SIZE.size)..-1]

    digest = OpenSSL::Digest.new('SHA256')
    cipher = OpenSSL::Cipher::Cipher.new(CIPHER)
    key_iv = OpenSSL::PKCS5.pbkdf2_hmac(POST_SECRET, salt, 10_000, KEY_SIZE + IV_SIZE, digest)

    cipher.key = key_iv[0..(KEY_SIZE - 1)]
    cipher.iv = key_iv[KEY_SIZE..-1]
    cipher.decrypt

    json_data = cipher.update(data) + cipher.final

    type, id = JSON.parse(json_data).values_at('type', 'id')
    return 422 if type.nil? || id.nil? || !TYPES.include?(type)

    REDIS.hset type, id, json_data
    201
  end
end
