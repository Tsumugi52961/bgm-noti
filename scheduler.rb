require 'rufus-scheduler'
require './bgm-noti.rb'

scheduler = Rufus::Scheduler.singleton

scheduler.every "30m", GetBangumis

scheduler.join