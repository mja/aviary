#!/usr/bin/env ruby
#
#  Created by Mark James Adams on 2007-05-14.
#  Copyright (c) 2007. All rights reserved.

require 'optparse'
require 'yaml'
require 'twitter_archiver'
require 'launchy'

AUTH_FILE = "twitauth.yml"

def prompt(default, *args)
  if not STDOUT.sync
    STDOUT.sync = true
    fix = true
  end
  print(*args)
  result = gets.strip
  if fix
    STDOUT.sync = false
  end
  return result.empty? ? default : result
end

def config(username)
  users = YAML.load_file(AUTH_FILE)
  config = Hash.new()

  key = "KYcLNiVtuTb5F55gWuVZQw"
  secret = "Vw36mGMxyhxxtfyz86UW9Fwtht4ZLmxerI4YUrRHLc"

  # Get a request token
  consumer = OAuth::Consumer.new(key, secret,
                               { :site => "http://api.twitter.com",
                                 :scheme => :header
  })
  request_token=consumer.get_request_token

  # Launch the authorization URL
  Launchy.open( request_token.authorize_url )

  # Prompt for a PIN number
  pin = prompt(nil,"Enter the Twitter PIN: ")
  
  if not pin.nil?
    # Get an access token
    access_token=request_token.get_access_token(:oauth_verifier => pin)
    config['token'] = access_token.token
    config['secret'] = access_token.secret
    users[username] = config
    File.open( AUTH_FILE, 'w' ) do |out|
      YAML.dump( users, out )
    end#File.open
  end#if not pin.nil?
end#config

begin

  CONFIG = YAML.load_file('config.yml')
  $options = {}
	$options[:tweet_path] = File.expand_path(CONFIG['archive_dir'])
  OptionParser.new do |opts|
    opts.banner = "Usage: aviary.rb --updates [new|all] --page XXX"
  
    $options[:updates] = :new
    opts.on("--updates [new|all]", [:new, :all], "Fetch only new or all updates") {|updates| $options[:updates] = updates}
    $options[:page] = 1
    opts.on("--page XXX", Integer, "Page") {|page| $options[:page] = page}
    $options[:new_account] = nil
    opts.on("--add XXX", String, "NewAccount") {|account| $options[:new_account] = account}
    $options[:only] = nil
    opts.on("--only XXX", String, "OnlyAccount") {|account| $options[:only] = account}
    $options[:debug] = nil
    opts.on("-d", "--debug", "Run verbosely") { |v| $options[:debug] = v }
  end.parse!

  if [:updates].map {|opt| $options[opt].nil?}.include?(nil)
    puts "Usage: aviary.rb --updates [new|all] --page XXX --add XXX --only XXX --debug"
    exit
  end

  if not $options[:new_account].nil?
    config($options[:new_account])
  end

  USERS = YAML.load_file(AUTH_FILE)

  case $options[:updates]
  when :new
    updates_only = true
  else :all
    updates_only = false
  end
 
  USERS.each { |user, auth|
    next unless ($options[:only].nil? or $options[:only]==user)
    token = auth['token']
    secret = auth['secret']

    ta = TwitterArchiver.new(user, token, secret, $options[:tweet_path], $options[:debug])
    ta.hark_timeline(updates_only, $options[:page]) # Get timeline
    ta.hark_mentions(updates_only, $options[:page]) # Get last 800 mentions
    ta.hark_messages(updates_only, $options[:page]) # Get direct messages sent to me
    ta.hark_messages_sent(updates_only, $options[:page]) # Get direct messages I sent
    ta.find_missing_replies # Look to see if we're missing any tweets we've replied to
    ta.try_to_download_replies # Try to download those missing messages
    ta.log_replies() # Make sure to save the list of missing messages
  }

  
rescue Errno::ENOENT => e
  puts "Whoops!"
  puts "#{e.message}" unless $options[:debug]
  puts "There is no configuration file."
  puts "Place your username and password in a file called `config.yml`. See config-example.yml."
  puts e.backtrace unless $options[:debug]
rescue RetrieveError => e
  puts "Nuts: #{e.reason}" unless not $options[:debug]
rescue StandardError => e
  puts "Caught an error... Logging replies"
  ta.log_replies()
  puts "Done"
  puts e.message unless not $options[:debug]
  puts e.backtrace unless not $options[:debug]
end



