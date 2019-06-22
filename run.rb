# ニコニコ動画の動画音声をボイスチャットに流すボット

require 'mechanize'
require 'json'
require 'net/https'
require 'open-uri'
require 'discordrb'
require 'dotenv'
Dotenv.load

module Niconico

  def self.receive(video_id)
    agent = Mechanize.new
    watch_response = agent.get("http://www.nicovideo.jp/watch/sm#{video_id}").search('//*[@id="js-initial-watch-data"]').attribute('data-api-data').value
    watch_response = JSON.parse(watch_response)

    open("watch_response.json","w") do |i|
      i.print watch_response.to_json
    end

    # old server
    if watch_response["video"]["dmcInfo"] == nil then
      return VideoInfo.new( watch_response["video"]["id"].slice(/\d+/).to_i,
                            watch_response["video"]["smileInfo"]["url"],
                            "smile")
    # new server
    else
      return DmcInfo.new(watch_response).receive
    end
  end


  class VideoInfo
    attr_reader :id, :name

    def initialize(id, url, type, dmc_info: nil)
      @id = id
      @url = url
      @server_type = type
      @dmc_info = dmc_info
      @name = ""
    end

    def type
      @server_type
    end

    def access(&block)
      heart_beat = start_heart_beat
      block.call(@url)
      heart_beat.kill

      self
    end

    def smile?
      if @server_type == "smile" then
        return true
      else
        return false
      end
    end

    def dmc?
      if @server_type == "dmc" then
        return true
      else
        return false
      end
    end

    private

    def start_heart_beat
      if self.dmc? then
        thread = Thread.new do
          loop do
            url = @dmc_info.session_url + "/" + @dmc_info.dmc_session_response["data"]["session"]["id"] + "?_format=json&_method=PUT"
            uri = URI.parse(url)
            request = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' =>'application/json'})
            request.body = {"session" => @dmc_info.dmc_session_response["data"]["session"]}.to_json
            response = nil

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            http.start do |http|
              http.options(url, {"Access-Control-Request-Headers" => "content-type", "Access-Control-Request-Method" => "POST"})
              response = http.request(request)
            end

            puts "beat: " + response.code
            sleep(30)
          end
        end

        return thread
      else
        return nil
      end
    end

  end

  class ContentSrcIdSets
    attr_writer :video_src_ids, :audio_src_ids

    def initialize
      @video_src_ids = Array.new
      @audio_src_ids = Array.new
    end

    def parse
      [
        {
          "content_src_ids" => [
            {
              "src_id_to_mux" => {
                "video_src_ids" => @video_src_ids,
                "audio_src_ids" => @audio_src_ids
              }
            }
          ]
        }
      ]
    end
  end

  class KeepMethod
    attr_writer :lifetime

    def initialize
      @lifetime = 0
    end

    def parse
      {
        "heartbeat" => {
          "lifetime" => @lifetime
        }
      }
    end
  end

  class Protocol
    attr_writer :name, :is_well_known_port, :is_ssl, :transfer_preset

    def initialize
      @name = String.new
      @is_well_known_port = false
      @is_ssl = false
      @transfer_preset = String.new
    end

    def parse
      if @is_well_known_port then
        port = "yes"
      else
        port = "no"
      end
      if @is_ssl then
        ssl = "yes"
      else
        ssl = "no"
      end

      {
        "name" => @name,
        "parameters" => {
          "http_parameters" => {
            "parameters" => {
              "http_output_download_parameters" => {
                "use_well_known_port" => port,
                "use_ssl" => ssl,
                "transfer_preset" => @transfer_preset
              }
            }
          }
        }
      }
    end
  end

  class SessionOperationAuth
    attr_writer :token, :signature

    def initialize
      @token = String.new
      @signature = String.new
    end

    def parse
      {
        "session_operation_auth_by_signature" => {
          "token" => @token,
          "signature" => @signature
        }
      }
    end
  end

  class ContentAuth
    attr_writer :auth_type, :content_key_timeout, :service_user_id

    def initialize
      @auth_type = String.new
      @content_key_timeout = 0
      @service_id = "nicovideo"
      @service_user_id = String.new
    end

    def parse
      {
        "auth_type" => @auth_type,
        "content_key_timeout" => @content_key_timeout,
        "service_id" => @service_id,
        "service_user_id" => @service_user_id
      }
    end
  end

  class ClientInfo
    attr_writer :player_id

    def initialize
      @player_id = String.new
    end

    def parse
      {
        "player_id" => @player_id
      }
    end
  end
  
  class DmcSessionRequest
    attr_accessor :recipe_id,
                  :content_id,
                  :lifetime,
                  :content_src_id_sets,
                  :keep_method,
                  :protocol,
                  :session_operation_auth,
                  :content_auth,
                  :client_info,
                  :priority

    def initialize
      @recipe_id = String.new
      @content_id = String.new
      @content_type = "movie"
      @content_src_id_sets = ContentSrcIdSets.new
      @timing_constraint = "unlimited"
      @keep_method = KeepMethod.new
      @protocol = Protocol.new
      @content_uri = String.new
      @session_operation_auth = SessionOperationAuth.new
      @content_auth = ContentAuth.new
      @client_info = ClientInfo.new
      @priority = 0
    end

    def parse
      {
        "session" => {
          "recipe_id" => @recipe_id,
          "content_id" => @content_id,
          "content_type" => @content_type,
          "content_src_id_sets" => content_src_id_sets.parse,
          "timing_constraint" => @timing_constraint,
          "keep_method" => @keep_method.parse,
          "protocol" => @protocol.parse,
          "content_uri" => @content_uri,
          "session_operation_auth" => @session_operation_auth.parse,
          "content_auth" => @content_auth.parse,
          "client_info" => @client_info.parse,
          "priority" => @priority
        }
      }
    end

    def to_json
      self.parse.to_json
    end

  end

  class DmcInfo

    attr_reader :dmc_session_response

    def initialize(dmc_watch_response)
      @dmc_watch_response = dmc_watch_response
    end

    def make_request
      dmc_session_request = DmcSessionRequest.new

      session_api = @dmc_watch_response["video"]["dmcInfo"]["session_api"]

      dmc_session_request.recipe_id = session_api["recipe_id"]
      dmc_session_request.content_id = session_api["content_id"]
      dmc_session_request.content_src_id_sets.video_src_ids = session_api["videos"]
      dmc_session_request.content_src_id_sets.audio_src_ids = session_api["audios"]
      dmc_session_request.keep_method.lifetime = session_api["heartbeat_lifetime"]
      dmc_session_request.protocol.name = session_api["protocols"][0]
      dmc_session_request.protocol.is_well_known_port = session_api["urls"][0]["is_well_known_port"]
      dmc_session_request.protocol.is_ssl = session_api["urls"][0]["is_ssl"]
      session_api["transfer_presets"].each do |i|
        dmc_session_request.protocol.transfer_preset << i
      end
      dmc_session_request.session_operation_auth.token = session_api["token"]
      dmc_session_request.session_operation_auth.signature = session_api["signature"]
      dmc_session_request.content_auth.auth_type = session_api["auth_types"]["http"]
      dmc_session_request.content_auth.content_key_timeout = session_api["content_key_timeout"]
      dmc_session_request.content_auth.service_user_id = session_api["service_user_id"]
      dmc_session_request.client_info.player_id = session_api["player_id"]
      dmc_session_request.priority = session_api["priority"]

      dmc_session_request
    end

    def session_url
      @dmc_watch_response["video"]["dmcInfo"]["session_api"]["urls"][0]["url"]
    end

    def receive
      dmc_session_request = self.make_request
      uri = URI.parse(self.session_url + "?_format=json")
      req = Net::HTTP::Post.new(uri.request_uri, {'Content-Type' =>'application/json'})
      req.body = dmc_session_request.to_json
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      res = nil
      http.start do |h|
        res = h.request(req)
      end
      @dmc_session_response = JSON.parse(res.body)

      open("dmc_session_response.json","w") do |i|
        i.print @dmc_session_response.to_json
      end

      return VideoInfo.new(self.id, @dmc_session_response["data"]["session"]["content_uri"], "dmc", dmc_info: self)
    end

    def id
      @dmc_watch_response["video"]["id"].slice(/\d+/).to_i
    end
  end
end

bot = Discordrb::Commands::CommandBot.new(
  token: ENV["TOKEN"],
  client_id: ENV["CLIENT_ID"],
  prefix: ENV["PREFIX"])

bot.command :up do |event|
  begin
    channel = event.author.voice_channel
  rescue RestClient::BadRequest => exception
    event << "#{event.author.name}がボイスチャンネルに参加していないか、Discordサーバに問題があります。"
  end
  bot.voice_connect(channel)
  event.voice.filter_volume = 0.2
  event << "Connect #{channel.name}"
end

bot.command :play do |event, video_id|
  begin
    channel = event.author.voice_channel
  rescue RestClient::BadRequest => exception
    event << "#{event.author.name}がボイスチャンネルに参加していないか、Discordサーバに問題があります。"
  end
  if event.voice.playing? then
    event << "再生中です。"
  else
    if event.voice.channel == event.author.voice_channel then
      if md = video_id.match(/sm(\d+)/) then
        event.respond "now loading..."
        video = Niconico.receive(md[1].to_s)
        video.access do |url|
          event.voice.play_io(open(url))
          event.respond "completed!"
        end
      else
        event << "ERROR: 不正な引数です。"
      end
    else
      event << "#{event.voice.channel.name} に参加してください。"
    end
  end
end

bot.command :pause do |event|
  begin
    if event.voice.channel == event.author.voice_channel then
      event.voice.pause
    else
      event << "#{event.voice.channel.name} に参加してください。"
    end
    
  rescue RestClient::BadRequest => exception
    event << "あなたがボイスチャンネルに参加していないか、Discordサーバに問題があります。"
  rescue NoMethodError => exception
    event << "ボットがボイスチャンネルに接続していません。"
    event << "接続していた場合、 @denebola213#0795 まで"
  end
  
  event << ""
end

bot.command :continue do |event|
  begin
    if event.voice.channel == event.author.voice_channel then
      event.voice.continue
    else
      event << "#{event.voice.channel.name} に参加してください。"
    end
    
  rescue RestClient::BadRequest => exception
    event << "あなたがボイスチャンネルに参加していないか、Discordサーバに問題があります。"
  rescue NoMethodError => exception
    event << "ボットがボイスチャンネルに接続していません。"
    event << "接続していた場合、 @denebola213#0795 まで"
  end
  
  event << ""
end

bot.command :stop do |event|
  begin
    if event.voice.channel == event.author.voice_channel then
      event.voice.stop_playing
    else
      event << "#{event.voice.channel.name} に参加してください。"
    end
    
  rescue RestClient::BadRequest => exception
    event << "あなたがボイスチャンネルに参加していないか、Discordサーバに問題があります。"
  rescue NoMethodError => exception
    event << "ボットがボイスチャンネルに接続していません。"
    event << "接続していた場合、 @denebola213#0795 まで"
  end
  
  event << ""
end

bot.command :volume do |event, volume_val|
  event.voice.volume = volume_val.to_f
  ""
end

bot.command :kill do |event|
  begin
    if event.voice.channel == event.author.voice_channel then
      event.voice.destroy
    else
      event << "#{event.voice.channel.name} に参加してください。"
    end
    
  rescue RestClient::BadRequest => exception
    event << "あなたがボイスチャンネルに参加していないか、Discordサーバに問題があります。"
  rescue NoMethodError => exception
    event << "ボットがボイスチャンネルに接続していません。"
    event << "接続していた場合、 @denebola213#0795 まで"
  end
  
  event << ""
end

bot.command :exit do |event|
  bot.stop
end


bot.run

#system("ffmpeg -i #{url} -movflags faststart -vn -c:a copy -bsf:a aac_adtstoasc sm#{video.id}.aac")