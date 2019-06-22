# ニコニコ動画の動画音声をボイスチャットに流すボット
require 'discordrb'
require 'dotenv'
Dotenv.load

bot = Discordrb::Commands::CommandBot.new(
  token: ENV["TOKEN"],
  client_id: ENV["CLIENT_ID"],
  prefix: ENV["PREFIX"])

bot.command :embed do |event|
  event.send_embed do |embed|
    embed.title = "title"
    embed.colour = 0xFF8000
    embed.url = "http://example.com/"
    embed.description = "description"
    embed.add_field(
      name: "field name left",
      value: "field value left",
      inline: true
    )
    embed.add_field(
      name: "field name right",
      value: "field value right",
      inline: true
    )
    embed.add_field(
      name: "field name under",
      value: "field value under",
      inline: false
    )
    embed.image = Discordrb::Webhooks::EmbedImage.new(url: 'https://www.ruby-lang.org/images/header-ruby-logo.png')
    embed.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new(url: 'https://discordapp.com/assets/e7a3b51fdac2aa5ec71975d257d5c405.png')
    embed.footer = Discordrb::Webhooks::EmbedFooter.new(
      text: "footer",
      icon_url: 'https://discordapp.com/assets/28174a34e77bb5e5310ced9f95cb480b.png'
    )
    embed.author = Discordrb::Webhooks::EmbedAuthor.new(
      name: 'deneola213',
      url: 'https://qiita.com/deneola213',
      icon_url: 'https://qiita-image-store.s3.amazonaws.com/0/122913/profile-images/1532764209'
    )
  end
end

bot.command :exit do |event|
  bot.stop
end

bot.run
