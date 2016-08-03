# encoding: utf-8
require 'open-uri'
require 'JSON'
require 'Mail'
require 'Erb'

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

  def self.start
    begin
      body = open(DMHY_URL).read
    rescue
      puts "---------------> Bad Network." and return
    end

    puts "---------------> Start getting bangumis updates."
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

      new_bangumis << new_bangumi
    end
    puts "---------------> Success fetching #{new_bangumis.count}bangumis."

    @bangumis = []
    subscriptions = JSON.parse(File.read("subscriptions.json"))
    subscriptions.each do |subscription|
      cur_exp = Regexp.new(subscription["rule"])
      new_bangumis.each do |bangumi|
        @bangumis << bangumi if cur_exp.match(bangumi.title)
      end
    end
    puts "---------------> Complete filt bangumis. #{@bangumis.count} new bangumis"

    Mail.defaults do
      delivery_method :smtp, { :address              => "your.smtp.server",
                               :port                 => 587,
                               :domain               => 'your.domain',
                               :user_name            => 'you@your.domain',
                               :password             => 'yourpassword',
                               :authentication       => 'plain',
                               :enable_starttls_auto => true  }
    end

    context = binding
    mail = Mail.new do
      text_part do
        body 'This is plain text'
      end

      html_part do
        content_type 'text/html; charset=UTF-8'
        body ERB.new(File.read('mail.html.erb')).result(context)
      end
    end

    mail.from     = 'you@your.domain'
    mail.to       = 'you@your.domain'
    mail.subject  = "#{@bangumis.count} bangumis updated #{Time.now.strftime("%Y%m%d")}"

    mail.deliver!
    puts "---------------> Succeed sending email."

  end
end

GetBangumis.start