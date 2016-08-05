require 'rufus-scheduler'
require './bgm-noti.rb'

scheduler = Rufus::Scheduler.singleton

scheduler.every("30m") do
  GetBangumis.start
end

scheduler.join