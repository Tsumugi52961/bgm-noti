# encoding: utf-8
require 'open-uri'
require 'json'
require 'mail'
require 'erb'
require 'logger'
require 'nokogiri'

class Bangumi
  attr_accessor :title, :link, :upload_at, :classfication, :fansub_id, :fansub, :title, :magnet_link, :size
  def initialize(options = {})
    options.each do |key, value|
      self.instance_variable_set("@#{key}", value)
    end
  end
end

class GetBangumis
  DMHY_URL = 'https://share.dmhy.org/'

  def initialize()
    @last_access = Time.at(Time.now.to_i - 864000)
    unless File.exist?(File.expand_path('../' + "bgm-noti.log", __FILE__))
      system "touch #{(File.expand_path('../' + 'bgm-noti.log', __FILE__))}"
    end
    @logger = Logger.new File.expand_path('../' + "bgm-noti.log", __FILE__)
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
      body = Nokogiri::HTML(open(DMHY_URL))
    rescue
      puts "---------------> Bad Network."
      @logger.warn("Bad Network")
      return
    end

    # parsing html body for bangumis data
    new_bangumis = []
    body.css("tbody > *").each do |item|
      new_bangumi = Bangumi.new()
      new_bangumi.upload_at     = item.at_xpath("./td[@width]/span").text
      new_bangumi.classfication = item.at_xpath("./td/a[@href]//font").text

      fansub = item.at_xpath("./td[@class='title']/span[@class='tag']/a[@href]")
      new_bangumi.fansub_id     = fansub.at_xpath("./@href").text.split('/')[-1] if !fansub.nil?
      new_bangumi.fansub        = fansub.text.gsub(/[\n\t]/, '') if !fansub.nil?

      new_bangumi.link          = "https://share.dmhy.org" + item.at_xpath("./td[@class='title']/a[@href]/@href").text
      new_bangumi.title         = item.at_xpath("./td[@class='title']/a[@href]").text.gsub(/[\n\t]/, '')
      new_bangumi.magnet_link   = item.at_xpath("./td[@nowrap]/a[@class][@title]/@href").text
      new_bangumi.size          = item.at_xpath("./td[@nowrap]/a[@class][@title]/../following-sibling::td").text

      break if Time.parse(new_bangumi.upload_at + " UTC") - Time.zone_offset("+08:00") < @last_access
      new_bangumis << new_bangumi
    end
    puts "---------------> Success fetching #{new_bangumis.count} bangumis."
    @logger.info("Fetching #{new_bangumis.count} bangumis.")
    @logger.info("@last_access updates: #{@last_access} => #{Time.now}")
    @last_access = Time.now

    # filtering by subscriptions
    @bangumis = []
    subscriptions = JSON.parse(File.read(load_file("subscriptions.json")))
    subscriptions.each do |subscription|
      cur_exp = Regexp.new(subscription["rule"])
      new_bangumis.each do |bangumi|
        @bangumis << [subscription["name"], bangumi] if (bangumi.fansub_id.to_i == subscription["fansub_id"] || subscription["fansub_id"].nil?) && cur_exp.match(bangumi.title)
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

      @subject = @bangumis.map{|b| b[0]}.uniq[0..1].join('、') + (@bangumis.map{|b| b[0]}.uniq.count > 2 ? "等 #{@bangumis.map{|b| b[0]}.uniq.count} 部新番" : '') + '更新啦！'

      mail.from     = mail_config["mail"]["from"]
      mail.to       = mail_config["mail"]["to"]
      mail.subject  = (mail_config["mail"]["subject"].nil? || mail_config["mail"]["subject"].blank?) ? @subject : eval(mail_config["mail"]["subject"])

      mail.deliver!
      puts "---------------> Succeed sending email."
      @logger.info("Sending #{@bangumis.count} bangumi(s).")
    end
  end

  private
  def load_file filename
    File.expand_path('../' + filename, __FILE__)
  end
end

if __FILE__ == $0
  GetBangumis.new.call
end
