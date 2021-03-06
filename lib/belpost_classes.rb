# frozen_string_literal: true

require 'singleton'

# Belpost module
module Belpost
  # Telegram class
  class Tlg < Telegram::Bot::Client
    include Singleton

    def initialize
      super Belpost::Config.instance.options['tg_token']
    end
  end

  def self.telegram
    Belpost::Tlg.instance
  end

  # Exception with message, sent to chat
  class Error < StandardError
    attr_reader :to_chat

    def initialize(text)
      super text
      @to_chat = text
    end
  end
end
