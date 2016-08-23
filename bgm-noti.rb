# encoding: utf-8
require 'open-uri'
require 'json'
require 'mail'
require 'erb'
require 'logger'

class Bangumi
  attr_accessor :title, :upload_at, :classfication, :fansub_id, :fansub, :title, :magnet_link, :size
  def initialize(options = {})
    options.each do |key, value|
      self.instance_variable_set("@#{key}", value)
    end
  end
end

class GetBangumis
  DMHY_URL = 'https://share.dmhy.org/'
  TIME = %q{<td.*>\s*.+<span.*>(.*)</span></td>\s+}
  CLASSFICATION = %q{<td.*>\s+<a[^>]+>\s+(?:<b>)?<font.+>(\S+)</font>(?:</b>)?</a>\s+</td>\s+}
  TITLE_WITH_TAG = %q{<td class="title">\s+(?:<span class="tag">\s+<a  href=[^_]+_id/(\d+).+\s+(\S+?)</a></span>)?\s+<a[^>]+>\s+(.+)</a>\s+.*?</td>\s+}
  MAGNET_LINK_AND_SIZE = %q{<td nowrap="nowrap" align="center"><a class="download-arrow arrow-magnet" [^h]+href="(.*)">&nbsp;</a></td>\s+<td nowrap="nowrap" align="center">(\S+)<\/td>}

  def initialize()
    @last_access = Time.at(Time.now.to_i - 86400)
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
      body = open(DMHY_URL).read
    rescue
      puts "---------------> Bad Network."
      @logger.warn("Bad Network")
      return
    end

    # parsing html body for bangumis data
    bangumi_list = body.scan(Regexp.new(TIME + CLASSFICATION + TITLE_WITH_TAG + MAGNET_LINK_AND_SIZE))

    new_bangumis = []
    bangumi_list.each do |bangumi|
      new_bangumi = Bangumi.new(upload_at: bangumi[0],
                                classfication: bangumi[1],
                                fansub_id: bangumi[2],
                                fansub: bangumi[3],
                                title: bangumi[4],
                                magnet_link: bangumi[5],
                                size: bangumi[6])

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
        @bangumis << bangumi if bangumi.fansub_id.to_i == subscription["fansub_id"] && cur_exp.match(bangumi.title)
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

      mail.from     = mail_config["mail"]["from"]
      mail.to       = mail_config["mail"]["to"]
      mail.subject  = eval(mail_config["mail"]["subject"])

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
