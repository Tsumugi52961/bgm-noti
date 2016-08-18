require 'rufus-scheduler'
require File.expand_path('../bgm-noti.rb', __FILE__)

scheduler = Rufus::Scheduler.singleton

scheduler.every "30m", GetBangumis

scheduler.join