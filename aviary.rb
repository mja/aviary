#!/usr/bin/env ruby
#
#  Created by Mark James Adams on 2007-05-14.
#  Copyright (c) 2007. All rights reserved.

require 'rubygems'
require 'hpricot'
require 'restclient'
require 'uri'
require 'fileutils'
require 'optparse'
require 'yaml'
require 'oauth'


# Exchange your oauth_token and oauth_token_secret for an AccessToken instance.
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

def hark(user, password, since_id, page)
  
  FileUtils.mkdir_p $options[:user] # Create a directory to hold the tweets
  
  listening = true
  
  while listening do # parse the account archive until we come to the last page (all)
                     # or we see a tweet we've alrady downloaded
  
    begin
			# Exchange our oauth_token and oauth_token secret for the AccessToken instance.
			access_token = prepare_access_token($options[:token], $options[:secret])
																					
			# use the access token as an agent to get the home timeline
			# response = access_token.request(:get, "http://api.twitter.com/1/statuses/home_timeline.json")
      
      unless since_id.nil? 
        since_id_parameter = "&since_id=#{since_id}"
      else
        since_id_parameter = ""
      end

      page_parameter = "&page=#{page}"
      count_parameter = "count=200"
			screen_name_parameter = "&screen_name=jmartindf"

      query = count_parameter + since_id_parameter + page_parameter + screen_name_parameter
      
      user_timeline_url = 'http://api.twitter.com/1/statuses/user_timeline.xml?' + query
			user_timeline_resource = access_token.request(:get, user_timeline_url)
      # user_timeline_resource = RestClient::Resource.new(user_timeline_url, :user => user, :password => password)

      puts "Fetching #{user_timeline_url}"
      user_timeline_xml = user_timeline_resource.body
			File.open("debug.log", 'w') { |data| data << user_timeline_resource.body }
      puts "Retrieved page #{page} ..."
      
      tweets = (Hpricot(user_timeline_xml)/"status")
      puts "Parsing #{tweets.length} tweets..."

      tweets.each {|tweet|

       id = tweet.at("id").inner_html
       
       puts "Saving tweet #{id}" 
       File.open("#{$options[:user]}/#{id}.xml", 'w') { |tweet_xml| tweet_xml << tweet.to_s}
              
      }

      unless tweets.empty?
        page = page + 1
      else
        listening = false
      end
     rescue RestClient::Unauthorized => e
       puts "Could not authenticate with Twitter. Doublecheck your username (#{user}) and password"
       listening = false
     rescue RestClient::RequestFailed => e
       puts "Twitter isn't responding: #{e.message}"
       listening = false
     end
  end # listening
  
end

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
  $options[:pass] = CONFIG['password']
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

  hark($options[:user], $options[:pass], since_id, $options[:page])
  
rescue Errno::ENOENT
  puts "Whoops!"
  puts "There is no configuration file."
  puts "Place your username and password in a file called `config.yml`. See config-example.yml."
end



