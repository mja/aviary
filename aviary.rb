#!/usr/bin/env ruby
#
#  Created by Mark James Adams on 2007-05-14.
#  Copyright (c) 2007. All rights reserved.

require 'rubygems'
require 'hpricot'
require 'uri'
require 'fileutils'
require 'optparse'
require 'yaml'
require 'oauth'
require 'time'

class RetrieveError < StandardError
  attr_reader :reason
  def initialize(reason)
    @reason = reason
  end
end

class FailWhaleError < StandardError
  attr_reader :reason
  def initialize(reason)
    @reason = reason
  end
end

class TwitterArchiver
  def prepare_access_token(oauth_token, oauth_token_secret)
    consumer = OAuth::Consumer.new("APIKey", "APISecret",
                                   { :site => "http://api.twitter.com",
                                     :scheme => :header
    })
    # now create the access token object from passed values
    token_hash = { :oauth_token => oauth_token,
      :oauth_token_secret => oauth_token_secret
    }
    access_token = OAuth::AccessToken.from_hash(consumer, token_hash )
    return access_token
  end

  def initialize(user, token, secret)
    @user = user
    @token = token
    @secret = secret
    @access_token = prepare_access_token($options[:token], $options[:secret])
    @replies = Array.new()
    File.foreach("#{@user}/replies.txt") { |line|
      track_reply(line.strip)
    }
  end

  def log_replies()
    File.open("#{@user}/replies.txt", 'w') { |rf|
      @replies.each { |reply|
        rf << reply.to_s << "\n"
      }
    }
  end
 
  def track_reply(id)
    @replies.push(id)
  end

  def got_reply(id)
    @replies.delete(id)
  end

  def hark(since_id, page)
    
    FileUtils.mkdir_p @user # Create a directory to hold the tweets
    
    listening = true
    
    # Exchange our oauth_token and oauth_token secret for the AccessToken instance.
    
    while listening do # parse the account archive until we come to the last page (all)
                       # or we see a tweet we've alrady downloaded
    
      begin
        unless since_id.nil? 
          since_id_parameter = "&since_id=#{since_id}"
        else
          since_id_parameter = ""
        end

        page_parameter = "&page=#{page}"
        count_parameter = "count=200"
        screen_name_parameter = "&screen_name=#{@user}"

        query = count_parameter + since_id_parameter + page_parameter + screen_name_parameter

        user_timeline_url = 'http://api.twitter.com/1/statuses/user_timeline.xml?' + query
        puts "Fetching #{user_timeline_url}"
        user_timeline_resource = @access_token.request(:get, user_timeline_url)
        user_timeline_xml = user_timeline_resource.body
        File.open("debug.log", 'w') { |data| data << user_timeline_xml }
        puts "Retrieved page #{page} ..."
        hp = Hpricot(user_timeline_xml)
        tweets = (hp/"status")
        if tweets.length == 0
          body = (hp/"body")
          raise FailWhaleError, "Fail Whale. Wait 5 seconds and try again" unless body.length == 0 # Fail Whale HTML page
        end
        puts "Parsing #{tweets.length} tweets..."
        tweets.each {|tweet|

         id = tweet.at("id").inner_html
         
         puts "Saving tweet #{id}" 
         save_tweet_disk(id, tweet)
        }

        unless tweets.empty?
          page = page + 1
        else
          listening = false
        end
      rescue FailWhaleError => e
        puts e.reason
        sleep(5)
        retry
       # rescue RestClient::Unauthorized => e
       #   puts "Could not authenticate with Twitter. Doublecheck your username (#{user}) and password"
       #   listening = false
       # rescue RestClient::RequestFailed => e
       #   puts "Twitter isn't responding: #{e.message}"
       #   listening = false
       end
    end # listening
    
  end

  def check_status_disk(id)
    $statuses = Array.new
    FileUtils.mkdir_p @user
    Dir.new(@user).select {|file| file =~ /\d+.xml$/}.each{|id_xml| 
      $statuses.push(id_xml.gsub('.xml', '').to_i)
    }
    return $statuses.index(id.to_i)
  end

  def get_single_tweet(id)
    tweet_url = "http://api.twitter.com/1/statuses/show/#{id}.xml"
    puts "Retrieving tweet " + id
    tweet_resource = @access_token.request(:get, tweet_url)
    tweet_xml = tweet_resource.body
    tweet = (Hpricot(tweet_xml)/"status").first
    error = (Hpricot(tweet_xml)/"hash").first
    raise RetrieveError, "auth problem?" unless error.nil?
    return tweet
  end

  def save_tweet_disk(id, tweet)
    begin
    if not check_status_disk(id)
      if tweet.nil?
        while tweet.nil? do
          tweet = get_single_tweet(id)
        end#while tweet.nil? do
      end#if tweet.nil?
      at = Time.parse(tweet.at("created_at").inner_html).iso8601
      puts "Saving tweet #{id}" 
      File.open("#{@user}/#{id}.xml", 'w') { |tweet_xml| tweet_xml << tweet.to_s}
      reply_to = tweet.at("in_reply_to_status_id").inner_html
      if (not reply_to.nil?) and (not reply_to.eql?(""))
        track_reply(reply_to)
      end#if reply_to
    else #status is on disk. load it and check for replies
      fn = "#{@user}/#{id}.xml"
      tweet = (Hpricot(open(fn))/"status")
      reply_to = tweet.at("in_reply_to_status_id").inner_html
      if (not reply_to.nil?) and (not reply_to.eql?(""))
        track_reply(reply_to)
      end#if reply_to
    end#if status already exists
    rescue RetrieveError => e
      puts "Couldn't download tweet #{e.reason}"
    end#begin block
  end#def save_tweet

end

# Exchange your oauth_token and oauth_token_secret for an AccessToken instance.


# concatinate an array of XML status files into a single XML file
def concatenate(archive)
  File.open("#{$user}.xml", "w") { |archive_xml|
    builder = Builder::XmlMarkup.new
    builder.instruct!
    builder.statuses do |b|
      builder << "\n"
      archive.each {|tweet| b << tweet.gsub('<?xml version="1.0" encoding="UTF-8"?>' + "\n", "")}
    end

    archive_xml << builder
  }
end

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

  $statuses = Array.new
  FileUtils.mkdir_p $options[:user]
  Dir.new($options[:user]).select {|file| file =~ /\d+.xml$/}.each{|id_xml| 
    $statuses.push(id_xml.gsub('.xml', '').to_i)
  }

  case $options[:updates]
  when :new
    # find the most recent status
    since_id = $statuses.sort.reverse.first
  else :all
    since_id = nil
  end
  
  ta = TwitterArchiver.new($options[:user], $options[:token], $options[:secret])
  ta.hark(since_id, $options[:page])
  ta.log_replies()
  
rescue Errno::ENOENT
  puts "Whoops!"
  puts "There is no configuration file."
  puts "Place your username and password in a file called `config.yml`. See config-example.yml."
rescue StandardError
  ta.log_replies()
end



