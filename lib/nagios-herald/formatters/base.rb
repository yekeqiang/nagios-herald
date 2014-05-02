# Formatter objects know best about how to create and format content.
# The Base class defines several variables and methods that can be used in subclasses.
# Nearly all of them can be overridden. Subclasses can also extend functionality and
# call on helpers.

# Dear Reader,
# There is a brittle, un-OOP pattern in this class, but it gets the job done
# because sometimes "working" is better than "elegant" or "correct".
# Your exercise, should you choose to take it on, is to devise a better way
# for a formatter to know which content to generate based on the message type.
# THIS IS ESPECIALLY IMPORTANT FOR SUBCLASSES THAT OVERRIDE METHODS!
# Hit me with your best shot.

require 'tmpdir'
require 'nagios-herald/logging'
require 'nagios-herald/util'
require 'nagios-herald/formatter_loader'

module NagiosHerald
  class Formatter
    include NagiosHerald::Logging
    include NagiosHerald::Util

    attr_accessor :attachments  # this is probably more appropriate in the Message class
    attr_accessor :html
    attr_accessor :sandbox # @sandbox is the place to save attachments, possibly a tempdir
    attr_accessor :state_type
    attr_accessor :tag
    attr_accessor :text

    def initialize(options)
      @attachments = []
      @html = ""
      @message_type = options[:message_type].downcase
      @nagios_url = options[:nagiosurl]
      @sandbox  = get_sandbox_path
      @state_type = get_nagios_var("NAGIOS_SERVICESTATE") != "" ? "SERVICE" : "HOST"
      @tag  = ""
      @text = ""

    end

    def self.formatters
      @@formatters ||= {}
    end

    # Public: When subclassed formatters are instantiated, add them to the @@formatters hash.
    # The key is the downcased and snake_cased name of the class file (i.e. check_disk);
    # the value is the actual class (i.e. CheckDisk) so that we can easily
    # instantiate formatters when we know the formatter name.
    # Learned this pattern thanks to the folks at Chef and @jonlives.
    # See https://github.com/opscode/chef/blob/11-stable/lib/chef/knife.rb#L79#L83
    #
    # Returns the formatters hash.
    def self.inherited(subclass)
      subclass_base_name = subclass.name.split('::').last
      subclass_base_name.gsub!(/[A-Z]/) { |s| "_" + s } # replace uppercase with underscore and lowercase
      subclass_base_name.downcase!
      subclass_base_name.sub!(/^_/, "")   # strip the leading underscore
      formatters[subclass_base_name] = subclass
    end

    # Public: Concatenates text content.
    #
    # Returns a string containing all text content.
    def add_text(text)
      @text += text
    end

    # Public: Concatenates HTML content.
    #
    # Returns a string containing all HTML content.
    def add_html(html)
      @html += html
    end

    # Public: Add an attachment's path to an array.
    #
    # Returns the array of attachment paths.
    def add_attachment(path)
      @attachments << path
    end

    #
    # format the content
    #

    # Public: Appends a newline in text and HTML format.
    # Generates text and HTML output.
    def format_line_break
      add_text "\n"
      add_html "<br>"
    end

    # Public: Formats the information about the host that's being alerted on.
    # Generates text and HTML output.
    def format_host_info
      notification_type = get_nagios_var("NAGIOS_NOTIFICATIONTYPE")
      hostname          = get_nagios_var("NAGIOS_HOSTNAME")
      service_desc      = get_nagios_var("NAGIOS_SERVICEDESC")
      add_text "Host: #{hostname} "
      add_html "<br><b>Host</b>: #{hostname} "
      if !service_desc.nil? and !service_desc.empty?
        add_text "Service: #{service_desc}\n"
        add_html "<b>Service</b>: #{service_desc}<br/>"
      else
        # we need a trailing newline if no service description
        format_line_break
      end
      format_line_break
    end

    # Public: Formats information about the state of the thing being alerted on
    # where 'thing' is either HOST or SERVICE.
    # Generates text and HTML output.
    def format_state_info
      state         = get_nagios_var("NAGIOS_#{@state_type}STATE")
      duration      = get_nagios_var("NAGIOS_#{@state_type}DURATION")
      last_duration = get_nagios_var("NAGIOS_LAST#{@state_type}STATE")
      attempts      = get_nagios_var("NAGIOS_#{@state_type}ATTEMPT")
      max_attempts  = get_nagios_var("NAGIOS_MAX#{@state_type}ATTEMPTS")
      add_text "State is now: #{state} for #{duration} (was #{last_duration}) after #{attempts} / #{max_attempts} checks\n"
      if state.eql? 'OK' or state.eql? 'UP'
          add_html "State is now: <b>#{state}</b> for <b>#{duration}</b> (was #{last_duration}) after <b>#{attempts} / #{max_attempts}</b> checks<br/>"
      else
          add_html "State is now: <b><font style='color:red'>#{state}</font></b> for <b>#{duration}</b> (was #{last_duration}) after <b>#{attempts} / #{max_attempts}</b> checks<br/>"
      end
      format_line_break
    end

    # Public: Formats information about the notification.
    # Provides information such as the date and notification number.
    # Generates text and HTML output.
    def format_notification_info
      date   = get_nagios_var("NAGIOS_LONGDATETIME")
      number = get_nagios_var("NAGIOS_NOTIFICATIONNUMBER")
      add_text "Notification sent at: #{date} (notification number #{number})\n\n"
      add_html "Notification sent at: #{date} (notification number #{number})<br><br>"
    end

    # Public: Formats information provided plugin's output.
    # Generates text and HTML output.
    def format_additional_info
      output = get_nagios_var("NAGIOS_#{@state_type}OUTPUT")
      if !output.nil? and !output.empty?
        add_text "Additional Info: #{unescape_text(output)}\n\n"
        add_html "<b>Additional Info</b>: #{output}<br><br>"
      end
    end

    # Public: Formats information provided plugin's *long* output.
    # Generates text and HTML output.
    def format_additional_details
      long_output = get_nagios_var("NAGIOS_LONG#{@state_type}OUTPUT")
      if !long_output.nil? and !long_output.empty?
        add_text "Additional Details: #{unescape_text(long_output)}\n"
        add_html "<b>Additional Details</b>: <pre>#{unescape_text(long_output)}</pre><br><br>"
      end
    end

    # Public: Formats the notes information for this alert.
    # Generates text and HTML output.
    def format_notes
      notes = get_nagios_var("NAGIOS_#{@state_type}NOTES")
      if !notes.nil? and !notes.empty?
        add_text "Notes: #{unescape_text(notes)}\n\n"
        add_html "<b>Notes</b>: #{notes}<br><br>"
      end

      notes_url = get_nagios_var("NAGIOS_#{@state_type}NOTESURL")
      if !notes_url.nil? and !notes_url.empty?
        add_text "Notes URL: #{notes_url}\n\n"
        add_html "<b>Notes URL</b>: #{notes_url}<br><br>"
      end
    end

    # Public: Formats the action URL for this alert.
    # Generates text and HTML output.
    def format_action_url
      action_url = get_nagios_var("NAGIOS_#{@state_type}ACTIONURL")
      if !action_url.nil? and !action_url.empty?
        add_text "Action URL: #{action_url}\n\n"
        add_html "<b>Action URL</b>: #{action_url}<br><br>"
      end
    end

    # Public: Formats details for the state of the alert (if it's a service)
    # TODO: Nothing for HOST?
    def format_state_detail
      if @state_type == "SERVICE"
        format_notes
        format_additional_details
      end
      format_line_break
    end

    # FIXME: Looks like a dupe of #format_additional_info (used in pager alerts, it seems)
    def format_short_state_detail
      output   = get_nagios_var("NAGIOS_#{@state_type}OUTPUT")
      add_text = "#{output}\n"
      add_html = "#{output}<br>"
    end

    # Public: Formats the email recipients and URIs
    # Generates text and HTML output.
    def format_recipients_email_link
      hostname      = get_nagios_var("NAGIOS_HOSTNAME")
      if @state_type == "SERVICE"
        service_desc  = get_nagios_var("NAGIOS_SERVICEDESC")
        subject = "#{hostname} - #{service_desc}"
      else
        subject = "#{hostname}"
      end

      recipients      = get_nagios_var("NAGIOS_NOTIFICATIONRECIPIENTS")
      return if recipients.nil?
      recipients_list   = recipients.split(',')
      recipients_mail   = recipients_list.map {|n| n + "@etsy.com"}
      recipients_mail_str = recipients_mail.join(',')
      add_text "Sent to #{recipients}\n"
      add_html %Q(Sent to <a href="mailto:#{recipients_mail_str}?subject=#{subject}">#{recipients}</a><br>)
    end

    # Public: Formats the information about who ack'd the alert and when
    # Generates text and HTML output.
    def format_ack_info
      date    = get_nagios_var("NAGIOS_LONGDATETIME")
      author    = get_nagios_var("NAGIOS_#{@state_type}ACKAUTHOR")
      comment   = get_nagios_var("NAGIOS_#{@state_type}ACKCOMMENT")
      hostname  = get_nagios_var("NAGIOS_HOSTNAME")

      add_text "At #{date} #{author}"
      add_html "At #{date} #{author}"

      if @state_type == "SERVICE"
        desc = get_nagios_var("NAGIOS_SERVICEDESC")
        add_text " acknowledged #{desc} on #{hostname}.\n\n"
        add_html " acknowledged #{desc} on #{hostname}.<br><br>"
      else
        add_text " acknowledged #{hostname}.\n\n"
        add_html " acknowledged #{hostname}.<br><br>"

      end
      add_text "Comment: #{comment}" if comment
      add_html "Comment: #{comment}" if comment
    end

    # Public: Formats brief ack information.
    # Useful for pager messages.
    # Generates text and HTML output.
    def format_short_ack_info
      author    = get_nagios_var("NAGIOS_#{@state_type}ACKAUTHOR")
      comment   = get_nagios_var("NAGIOS_#{@state_type}COMMENT")
      hostname  = get_nagios_var("NAGIOS_HOSTNAME")

      add_text "#{author}  ack'd "
      add_html "#{author}  ack'd "

      if @state_type == "SERVICE"
        desc = get_nagios_var("NAGIOS_SERVICEDESC")
        add_text "#{desc} on #{hostname}.\n"
        add_html "#{desc} on #{hostname}.<br>"
      else
        add_text "#{hostname}.\n"
        add_html "#{hostname}.<br>"

      end
      add_text "Comment: #{comment}" if comment
      add_html "Comment: #{comment}" if comment
    end

    # Public: Formats the URI one can click to acknowledge an alert (i.e. in an email)
    # Generates text and HTML output.
    def format_alert_ack_url
      hostname  = get_nagios_var("NAGIOS_HOSTNAME")
      service_desc = get_nagios_var("NAGIOS_SERVICEDESC")

      if service_desc != ""
        url = "#{@nagios_url}/nagios/cgi-bin/cmd.cgi?cmd_typ=34&host=#{hostname}&service=#{service_desc}"
      else
        url = "#{@nagios_url}/nagios/cgi-bin/cmd.cgi?cmd_typ=33&host=#{hostname}"
      end
      url = URI.escape(url)
      add_text "Acknowledge this alert: #{url}\n"
      add_html "Acknowledge this alert: #{url}<br>"
    end

    #
    # structural bits and content generation
    #

    # Public: Starts a format section's HTML DIV block.
    #
    # *section_style_args - CSS-type attributes used to style the content.
    #
    # Example
    #
    #   start_section("color:green")
    #
    # Generates HTML DIV block with the requested style.
    def start_section(*section_style_args)
      if ! section_style_args.nil?
         style = section_style_args.join(';')
         add_html "<div style='#{style}'>"
      end
    end

    # Public: Ends a format section's HTML DIV block.
    def end_section
      add_html "</div>"
    end

    # Public: Wrapper for starting a format section, calling the format method,
    # and ending the section.
    def generate_section(section_name, *section_style_args)
      start_section(*section_style_args)
      self.send(section_name)
      end_section
    end

    # Public: Generate content for PROBLEM alerts.
    def generate_problem_content
      self.tag = "ALERT"
      case @message_type
      when "pager"
        generate_section("format_additional_info")
      else
        generate_section("format_host_info")
        generate_section("format_state_info")
        generate_section("format_additional_info")
        generate_section("format_action_url")
        generate_section("format_state_detail") # format_notes and format_additional_details for services
        generate_section("format_recipients_email_link")
        generate_section("format_notification_info")
        generate_section("format_alert_ack_url")
      end
    end

    # Public: Generate content for RECOVERY alerts.
    def generate_recovery_content
      self.tag = "OK"
      generate_section("format_host_info", "color:green")
      generate_section("format_state_info", "color:green")
      generate_section("format_additional_info", "color:green")
      generate_section("format_action_url", "color:green")
      generate_section("format_state_detail", "color:green") # format_notes and format_additional_details for services
      generate_section("format_recipients_email_link")
      generate_section("format_notification_info")
    end

    # Public: Generate content for ACKNOWLEGEMENT alerts
    def generate_ack_content
      self.tag = "ACK"
      generate_section("format_host_info")
      generate_section("format_ack_info")
    end

    # Public: Dispatch method to help generate content based on notification
    # type.
    #
    # nagios_notification_type - One of any valid Nagios notification types.
    #
    # Example
    #
    #   generate_content("PROBLEM")
    #
    def generate_content(nagios_notification_type)
      case nagios_notification_type
        when "PROBLEM", "FLAPPINGSTART"
          generate_problem_content
        when "RECOVERY", "FLAPPINGSTOP"
          generate_recovery_content
        when "ACKNOWLEDGEMENT"
          generate_ack_content
        else
          logger.fatal "Invalid Nagios notification type! Expecting something like PROBLEM or RECOVERY."
          exit 1
        end
    end

    # Public: Generates a subject.
    # Can, and probably should, be overridden in a subclass.
    def generate_subject
      hostname          = get_nagios_var("NAGIOS_HOSTNAME")
      service_desc      = get_nagios_var("NAGIOS_SERVICEDESC")
      notification_type = get_nagios_var("NAGIOS_NOTIFICATIONTYPE")
      state             = get_nagios_var("NAGIOS_#{@state_type}STATE")

      case @message_type
      when "email"
        subject="#{hostname}"
        subject += "/#{service_desc}" if service_desc != ""

        if @state_type == "SERVICE"
          subject="** #{notification_type} Service #{subject} is #{state} **"
        else
          subject="** #{notification_type} Host #{subject} is #{state} **"
        end
      when "pager"
        subject="#{hostname}"
        subject += "/#{service_desc}" if service_desc != ""

        if @state_type == "SERVICE"
          subject="#{notification_type} SVC #{subject} #{state}"
        else
          subject="#{notification_type} HST #{subject} #{state}"
        end
      end

      subject
    end

    # Public: Generates content body.
    # Can, and probably should, be overridden in a subclass.
    def generate_body
        nagios_notification_type = get_nagios_var('NAGIOS_NOTIFICATIONTYPE')
        generate_content(nagios_notification_type)
    end

    # Public: Creates a temporary directory in which to create files used in
    # attachments.
    #
    # Returns the path to a temporary directory.
    def get_sandbox_path
      @sandbox = Dir.mktmpdir if @sandbox.nil?
      return @sandbox
    end

    # Public: Does some housecleaning on the sandbox, if it exists.
    def clean_sandbox
      FileUtils.remove_entry @sandbox if File.directory?(@sandbox)
    end

  end
end
