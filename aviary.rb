#!/usr/bin/env ruby
#
#  Created by Mark James Adams on 2007-05-14.
#  Copyright (c) 2007. All rights reserved.

require 'nokogiri'
require 'uri'
require 'fileutils'
require 'optparse'
require 'yaml'
require 'oauth'
require 'time'
require 'twitter_archiver'

begin

  CONFIG = YAML.load_file('config.yml')
  $options = {}
  $options[:user] = CONFIG['username']
	$options[:secret] = CONFIG['secret']
	$options[:token] = CONFIG['token']
  OptionParser.new do |opts|
    opts.banner = "Usage: aviary.rb --updates [new|all] --page XXX"
  
    $options[:updates] = :new
    opts.on("--updates [new|all]", [:new, :all], "Fetch only new or all updates") {|updates| $options[:updates] = updates}
    $options[:page] = 1
    opts.on("--page XXX", Integer, "Page") {|page| $options[:page] = page}
  end.parse!

  if [:updates].map {|opt| $options[opt].nil?}.include?(nil)
    puts "Usage: aviary.rb --updates [new|all] --page XXX"
    exit
  end

  case $options[:updates]
  when :new
    updates_only = true
  else :all
    updates_only = false
  end
  
  ta = TwitterArchiver.new($options[:user], $options[:token], $options[:secret])
  ta.hark(updates_only, $options[:page], "http://api.twitter.com/1/statuses/user_timeline", false) # Get timeline
  ta.hark(updates_only, $options[:page], "http://api.twitter.com/1/statuses/mentions", false) # Get last 800 mentions
  ta.hark(updates_only, $options[:page], "http://api.twitter.com/1/direct_messages", true) # Get direct messages sent to me
  ta.hark(updates_only, $options[:page], "http://api.twitter.com/1/direct_messages/sent", true) # Get direct messages I sent
  ta.find_missing_replies # Look to see if we're missing any tweets we've replied to
  ta.try_to_download_replies # Try to download those missing messages
  ta.log_replies() # Make sure to save the list of missing messages
  
rescue Errno::ENOENT
  puts "Whoops!"
  puts "There is no configuration file."
  puts "Place your username and password in a file called `config.yml`. See config-example.yml."
rescue RetrieveError => e
  puts "Nuts: #{e.reason}"
rescue StandardError => e
  puts "Caught an error... Logging replies"
  ta.log_replies()
  puts "Done"
  puts e.message
end



