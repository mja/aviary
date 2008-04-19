#!/usr/bin/env ruby
#
#  Created by Mark James Adams on 2007-05-14.
#  Copyright (c) 2007. All rights reserved.

require 'rubygems'
require 'hpricot'
require 'builder'
require 'net/http'
require 'uri'
require 'fileutils'
require 'optparse'
require 'yaml'

def hark(page)
  
  FileUtils.mkdir_p $options[:user] # Create a directory to hold the tweets
  
  listening = true
  older = nil
  
  while listening do # parse the account archive until we come to the last page (all)
                     # or we see a tweet we've alrady downloaded
  
    Net::HTTP.start('twitter.com') { |twitter|
  
      home = Net::HTTP::Get.new(page)
      #home.basic_auth $options[:user], $options[:password]
      puts "Retrieving " + page + " ..."
      response = twitter.request(home)
  
      puts "Parsing..."
      tweets = Hpricot(response.body)
    
      # Parse the status update ids out of the URL for each entry
      entries = tweets/"a.entry-date"
  
      if entries.empty? then
        puts "Looks like Twitter is undergoing maintenance. Hang in there and try again later. Also, double check your username and password!"
        exit
      end
  
      entries.each {|meta|
        id = /\d+/.match(meta[:href]).to_s # TODO this will probably fail if user has digits in their name.
                                           # Perhaps we should get it from the #id instead?
        show = Net::HTTP::Get.new("/statuses/show/#{id}.xml")
        #show.basic_auth $options[:user], $options[:password]
    
        unless $statuses.include?(id) then # TODO also check that tweet is complete and valid
          puts "Retrieving tweet " + id
          status = twitter.request(show)
          File.open("#{$options[:user]}/#{id}.xml", 'w') { |tweet_xml| tweet_xml << status.body}
        else 
          puts "Already fetched tweet " + id
          # Stop if not asked to get all tweets
          unless $options[:updates] == :all then listening = false; break; end 
        end
      
      }
    
  
    older = (tweets/"div.pagination a").select {|link| link.inner_text =~ /Older/}.first
   } 
    unless older.nil?
      page = URI.parse(older[:href]).select(:path, :query).join('?')
    else
      listening = false # No more pages to parse, so stop listening.
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
  OptionParser.new do |opts|
    opts.banner = "Usage: aviary.rb --updates [new|all] --page XXX"
  
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
    $statuses.push(id_xml.gsub('.xml', ''))
  }

  hark("/#{$options[:user]}?page=#{$options[:page]}")
  
rescue Errno::ENOENT
  puts "Whoops!"
  puts "There is no configuration file."
  puts "Place your username and password in a file called `config.yml`. See config-example.yml."
end



