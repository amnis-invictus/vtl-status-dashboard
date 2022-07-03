# frozen_string_literal:true

require 'base64'
require 'bundler/setup'
require 'json'
require 'redis'
require 'sinatra'
require 'openssl'

TYPES = %w[internet pmg17 lan].freeze
DIGEST = OpenSSL::Digest.new('SHA256').freeze
CIPHER_NAME = 'AES-256-CBC'
MAGIC = 'Salted__'
SALT_SIZE = 8
KEY_SIZE = 32
IV_SIZE = 16
ITERATIONS = 10_000
REDIS = Redis.new url: ENV['REDIS_URL']
POST_SECRET = ENV.fetch('POST_SECRET')

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

    return 422 unless MAGIC == enc_data.slice!(0, MAGIC.size)

    salt = enc_data.slice!(0, SALT_SIZE.size)
    cipher = OpenSSL::Cipher::Cipher.new(CIPHER_NAME)
    key_iv = OpenSSL::PKCS5.pbkdf2_hmac(POST_SECRET, salt, ITERATIONS, KEY_SIZE + IV_SIZE, DIGEST)

    cipher.decrypt
    cipher.key = key_iv[0...KEY_SIZE]
    cipher.iv = key_iv[KEY_SIZE..]

    json_data = cipher.update(enc_data) + cipher.final

    type, name = JSON.parse(json_data).values_at('type', 'name')
    return 422 if type.nil? || name.nil? || !TYPES.include?(type)

    REDIS.hset type, name, json_data
    201
  end
end
