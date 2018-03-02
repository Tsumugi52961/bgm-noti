# encoding: utf-8
require 'json'
require 'mail'
require 'erb'
require 'logger'
require 'rss'
require 'rest-client'

class Bangumi
  attr_accessor :name, :title, :link, :uploaded_at, :classfication, :fansub_id, :fansub, :title, :magnet_link, :size
  def initialize(options = {})
    options.each do |key, value|
      self.instance_variable_set("@#{key}", value)
    end
  end
end

class GetBangumis
  DMHY_URL = 'https://share.dmhy.org/'
  DMHY_RSS = 'https://share.dmhy.org/topics/rss/rss.xml'
  REMOTE_PATH = ENV["REMOTE_PATH"]
  LOG_PATH = File.expand_path("../log/bgm-noti.log", __FILE__)

  def initialize()
    @last_access = Time.at(Time.now.to_i - 864000)
    unless File.exist?(LOG_PATH)
      system "touch #{LOG_PATH}"
    end
    @logger = Logger.new LOG_PATH
    @logger.level = Logger::INFO
    @logger.formatter = proc do |severity, datetime, progname, msg|
      date_format = datetime.strftime("%Y-%m-%d %H:%M:%S")
      if severity == "INFO" or severity == "WARN"
          "[#{date_format}] #{severity}  : #{msg}\n"
      else
          "[#{date_format}] #{severity} : #{msg}\n"
      end
    end
  end

  def call
    puts "---------------> Start getting bangumis updates."
    begin
      rss = RSS::Parser.parse(DMHY_RSS, false)
    rescue
      puts "---------------> Bad Network."
      @logger.warn("Bad Network")
      return
    end

    new_bangumis = []
    rss.items.each do |item|
      new_bangumi = Bangumi.new()
      new_bangumi.uploaded_at = item.pubDate.strftime("%F %T")
      new_bangumi.classfication = item.category.content
      new_bangumi.link = item.link
      new_bangumi.title = item.title
      new_bangumi.magnet_link = item.enclosure.url

      break if Time.parse(new_bangumi.uploaded_at + " UTC") - Time.zone_offset("+08:00") < @last_access
      new_bangumis << new_bangumi
    end
    puts "---------------> Success fetching #{new_bangumis.count} bangumis."
    @logger.info("Fetching #{new_bangumis.count} bangumis.")
    @logger.info("@last_access updates: #{@last_access} => #{Time.now}")
    @last_access = Time.now

    @bangumis = []
    subscriptions = JSON.parse(File.read(load_file("subscriptions.json")))
    subscriptions.each do |subscription|
      cur_exp = Regexp.new(subscription["rule"])
      new_bangumis.each do |bangumi|
        bangumi.name = subscription["name"]
        @bangumis << bangumi.tap{|b| b.name = subscription["name"]} if cur_exp.match(bangumi.title)
      end
    end
    puts "---------------> Complete filtering. #{@bangumis.count} updates."

    # sending email if bangumi updates
    if @bangumis.count == 0
      puts "---------------> Abort."
      @logger.info("No updates.")
    else
      mail_config = YAML.load_file(load_file "mail_config.yml")
      Mail.defaults do
        delivery_method :smtp, mail_config["delivery_method"].map{|k, v| {k.to_sym => v}}.reduce(:merge)
      end

      puts "---------------> Sending email ..."
      context = binding
      mail = Mail.new do
        text_part do
          content_type 'text/html; charset=UTF-8'
          body ERB.new(File.read(File.expand_path('../mail.text.erb', __FILE__))).result(context)
        end

        html_part do
          content_type 'text/html; charset=UTF-8'
          body ERB.new(File.read(File.expand_path('../mail.html.erb', __FILE__))).result(context)
        end
      end

      @subject = @bangumis.map(&:name).uniq[0..1].join('、') + (@bangumis.map(&:name).uniq.count > 2 ? "等 #{@bangumis.count} 部新番" : '') + '更新啦！'

      mail.from     = mail_config["mail"]["from"]
      mail.to       = mail_config["mail"]["to"]
      mail.subject  = (mail_config["mail"]["subject"].nil? || mail_config["mail"]["subject"].blank?) ? @subject : eval(mail_config["mail"]["subject"])

      mail.deliver!
      puts "---------------> Succeed sending email."
      @logger.info("Sending #{@bangumis.count} bangumi(s).")

      # request remote
      @bangumis.each do |bangumi|
        response = request_remote(bangumi)
        if response&.code == 200 || response&.code == 201
          @logger.info("Request succeed.")
        else
          @logger.error("Request failed! #{response.body}")
        end
      end
    end
  end

  private
  def request_remote(bangumi)
    body = {
      title: bangumi.title,
      classfication: bangumi.classfication,
      link: bangumi.link,
      uploaded_at: bangumi.uploaded_at,
      magnet_link: bangumi.magnet_link
    }
    RestClient.post "#{REMOTE_PATH}/bangumis", body
  end

  def load_file filename
    File.expand_path('../' + filename, __FILE__)
  end
end

if __FILE__ == $0
  GetBangumis.new.call
end

