require 'nagios-herald/messages/base'
require 'mail'

module NagiosHerald
  class Message
    class Pager < Message

      attr_accessor :subject
      attr_accessor :text

      def initialize(recipients, options = {})
        @replyto     = options[:replyto]
        @subject     = ""
        @text        = ""
        super(recipients, options)
      end

      def print
        puts "------------------"
        puts "Subject : #{@subject}"
        puts "------------------"
        puts @text
      end

      def send
        if @nosend
          self.print
          return
        end

        mail = Mail.new({
          :from    => @replyto,
          :to      => @recipients,
          :subject => @subject,
          :body    => @text
        })

        mail.deliver!
      end
    end
  end
end

