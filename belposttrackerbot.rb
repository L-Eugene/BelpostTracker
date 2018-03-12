# frozen_string_literal: true

require 'telegram/bot'
require 'singleton'
require 'yaml'

module Belpost
  # Configuration singleton
  class Config
    include Singleton

    attr_reader :options

    CONFIG_PATH = "#{__FILE__}.yml"

    def initialize
      @options = YAML.load_file(CONFIG_PATH)
    end
  end
end

$LOAD_PATH.unshift(
  File.join(File.dirname(__FILE__), Belpost::Config.instance.options['libdir'])
)

require 'db/belpost_model'
require 'log/belpost_logger'
require 'belpost_classes'

# Main Bot Class
class BelpostTrackerBot
  attr_reader :client, :chat

  def initialize
    @client = Belpost.telegram
  end

  def update_message(message)
    @chat = Belpost::Chat.find_or_create_by(chat_id: message.chat.id)

    meth = method_from_message(message.text)
    send(meth, message.text) if respond_to? meth.to_sym, true
  end

  def update_cq(cq)
    Belpost.log.debug "Callback_query: #{cq.data} #{cq.message.chat.id}"
  end

  def update(data)
    update = Telegram::Bot::Types::Update.new(data)

    update_message update.message unless update.message.nil?
    update_cq update.callback_query unless update.callback_query.nil?
  end

  def scan
    Belpost.log.info 'Starting scan'

    update_tracks
    drop_old_tracks

    Belpost.log.info 'Finish scan'
  end

  private

  HELP_MESSAGE = <<~TEXT
    */help* - print this help message
    */list* - list tracknumbers watched in this chat
    */add* _track_ _comment_ - add tracknumber to watchlist
    */delete* _track_ - delete tracknumber from watchlist
  TEXT

  def update_tracks
    Belpost::Track.find_each do |t|
      Belpost.log.info "Scanning #{t.number}"
      t.refresh if t.watched?
    end
  end

  def method_from_message(text)
    meth = (text || '').downcase.tr('_', ' ')
    [%r{\@.*$}, %r{\s.*$}, %r{^/}].each { |x| meth.gsub!(x, '') }

    Belpost.log.info "#{meth} command from #{chat.chat_id}"
    Belpost.log.debug "Full command is #{text}"

    "cmd_#{meth}"
  end

  def cmd_add(text)
    num = text.gsub(%r{/add[\s_]*}, '').split(%r{\s})
    track = Belpost::Track.find_or_create_by(number: num.shift)

    chat.add track, num.join(' ')
    chat.send_text 'Added track to this chat list'
  rescue StandardError
    log_exception $ERROR_INFO
  end

  def cmd_delete(text)
    num = text.gsub(%r{/delete\s*}, '')
    track = Belpost::Track.find_by(number: num)

    chat.unwatch track
    chat.send_text 'Removed track number from watch list'
  rescue StandardError
    log_exception $ERROR_INFO
  end

  def cmd_list(_)
    chat.send_text chat.status, 'HTML', chat.list_keyboard
  end

  def cmd_help(_)
    chat.send_text HELP_MESSAGE
  end

  def log_exception(error)
    Belpost.log.error error
    respond = error.respond_to? 'to_chat'
    chat.send_text respond ? error.to_chat : 'Invalid track number'
  end

  def drop_old_tracks
    cond = 'updated_at < DATE_SUB(NOW(), INTERVAL 4 MONTH)'
    Belpost::Track.where(cond).find_each do |t|
      t.chats.each do |c|
        msg = <<~MSG
          #{t.number} was not updated for too long, removing it from watchlist
          If you still want to watch it, add it again with /add_#{t.number}
        MSG
        c.send_text msg if c.enabled?
      end
      t.destroy
    end
  end
end
