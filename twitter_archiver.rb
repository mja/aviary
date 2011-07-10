#
#  Created by Mark James Adams on 2007-05-14.
#  Copyright (c) 2007. All rights reserved.

require 'nokogiri'
require 'uri'
require 'fileutils'
require 'oauth'
require 'time'

class RetrieveError < StandardError
  attr_reader :reason
  def initialize(reason)
    @reason = reason
  end
end

class RateLimit < StandardError
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
    key = "KYcLNiVtuTb5F55gWuVZQw"
    secret = "Vw36mGMxyhxxtfyz86UW9Fwtht4ZLmxerI4YUrRHLc"
    consumer = OAuth::Consumer.new(key, secret,
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

  def initialize(user, token, secret, root)
    @user = user
    @token = token
    @secret = secret
    @access_token = prepare_access_token($options[:token], $options[:secret])
    @replies = Array.new()
    @lost_replies = Array.new()
    @t_prefix = File.join(root, @user,"")
    @dm_prefix = File.join(root, @user,"dm")
    @replies_path = File.join(@t_prefix,"replies.txt")
    @lost_replies_path = File.join(@t_prefix,"lost_replies.txt")
    @t_node = "status"
    @dm_node = "direct_message"
    
    FileUtils.mkdir_p @t_prefix
    FileUtils.mkdir_p @dm_prefix

    File.foreach(@replies_path) { |line|
      track_reply(line.strip) unless line.nil?
    }
    File.foreach(@lost_replies_path) { |line|
      track_reply(line.strip, true)
    }
  end

  def log_replies()
    @replies.delete("")
    @lost_replies.delete("")
    @replies.compact!
    @lost_replies.compact!
    File.open(@replies_path, 'w') { |rf|
      @replies.each { |reply|
        rf << reply.to_s << "\n"
      }
    }
    File.open(@lost_replies_path, 'w') { |rf|
      @lost_replies.each { |reply|
        rf << reply.to_s << "\n"
      }
    }
  end
 
  def track_reply(id, missing=false)
    if missing
      @replies.delete(id)
      @lost_replies.push(id)
    else
      @lost_replies.delete(id)
      @replies.push(id)
    end
    @replies.uniq!
    @lost_replies.uniq!
    log_replies()
  end

  def get_most_recent_id(dm=false)
    $statuses = Array.new
    if dm
      dirname = @dm_prefix
    else
      dirname = @t_prefix
    end
    Dir.new(dirname).select {|file| file =~ /\d+.xml$/}.each{|id_xml| 
      $statuses.push(id_xml.gsub('.xml', '').to_i)
    }
    # find the most recent status
    last_id = $statuses.sort.reverse.first
  end

  def got_reply(id, missing=false)
    @replies.delete(id)
    @lost_replies.delete(id)
    @replies.uniq!
    @lost_replies.uniq!
    log_replies()
  end

  def find_missing_replies
    @replies.uniq!
    @replies.each { |id|
      pos = check_status_disk(id)
      if not pos.nil?
        puts "Found tweet #{id}"
        got_reply(id)
      end
    }
  end

  def hark(updates_only, page, api, dm=false)
    
    listening = true
   
    if updates_only
      since_id = get_most_recent_id(dm)
      since_id_parameter = "&since_id=#{since_id}"
    else
      since_id_parameter = ""
    end 

    if dm
      node = @dm_node
    else
      node = @t_node
    end
    
    count_parameter = "count=200"
    screen_name_parameter = "&screen_name=#{@user}"
    
    while listening do # parse the account archive until we come to the last page (all)
                       # or we see a tweet we've alrady downloaded
    
      begin

        page_parameter = "&page=#{page}"
        query = count_parameter + since_id_parameter + page_parameter + screen_name_parameter
        user_timeline_url = "#{api}.xml?" + query
        
        puts "Fetching #{user_timeline_url}"
        user_timeline_resource = @access_token.request(:get, user_timeline_url)
        user_timeline_xml = user_timeline_resource.body
        File.open(File.join(@t_prefix,"debug.log"), 'w') { |data| data << user_timeline_xml }
        puts "Retrieved page #{page} ..."
        hp = Nokogiri(user_timeline_xml)
        tweets = (hp/node)
        if tweets.length == 0
          body = (hp/"body")
          raise FailWhaleError, "Fail Whale. Wait 5 seconds and try again" unless body.length == 0 # Fail Whale HTML page
          hash = (hp/"hash")
          raise RetrieveError, hash.at("error").inner_html unless body.length == 0
        end
        puts "Parsing #{tweets.length} tweets..."
        tweets.each {|tweet|

         id = tweet.at("id").inner_html
         
         puts "Saving tweet #{id}" 
         save_tweet_disk(id, tweet, dm)
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
      rescue RetrieveError => e
        puts "Download failed: #{e.reason}"
        listening = false
       end
    end # listening
    
  end

  def check_status_disk(id)
    $statuses = Array.new
    Dir.new(@t_prefix).select {|file| file =~ /\d+.xml$/}.each{|id_xml| 
      $statuses.push(id_xml.gsub('.xml', '').to_i)
    }
    return $statuses.index(id.to_i)
  end

  def get_single_tweet(id)
    tweet_url = "http://api.twitter.com/1/statuses/show/#{id}.xml"
    puts "Retrieving tweet " + id
    tweet_resource = @access_token.request(:get, tweet_url)
    tweet_xml = tweet_resource.body
    tweet = (Nokogiri(tweet_xml)/"status").first
    error = (Nokogiri(tweet_xml)/"hash").first
    emsg = error.at('error').inner_html unless error.nil?
    if not emsg.nil? and ( emsg.include?("No status found with that ID.") or
                          emsg.include?("Not found") )
      track_reply(id, true)
    end
    if not emsg.nil? and emsg.include?("Rate limit exceeded")
      raise RateLimit, emsg
    end
    raise RetrieveError, "Tweet #{id}: #{emsg}" unless error.nil?
    return tweet
  end

  def try_to_download_replies
      @replies.each { |id|
        begin
        tweet = get_single_tweet(id)
        save_tweet_disk(id, tweet)
        got_reply(id)
        rescue RetrieveError => e
          puts "#{e.reason}"
        end
      }
  end

  def save_tweet_disk(id, tweet, dm=false)
    if dm
      fname = File.join(@dm_prefix, "#{id}.xml")
    else
      fname = File.join(@t_prefix, "#{id}.xml")
    end
    begin
    if not check_status_disk(id)
      if tweet.nil?
        while tweet.nil? do
          tweet = get_single_tweet(id)
        end#while tweet.nil? do
      end#if tweet.nil?
      at = Time.parse(tweet.at("created_at").inner_html).iso8601
      puts "Saving tweet #{id}" 
      File.open(fname, 'w') { |tweet_xml| tweet_xml << tweet.to_s}
      reply_to = tweet.at("in_reply_to_status_id").inner_html unless dm
      if (not reply_to.nil?) and (not reply_to.eql?(""))
        track_reply(reply_to)
      end#if reply_to
    else #status is on disk. load it and check for replies
      tweet = (Nokogiri(open(fname))/"status")
      reply_to = tweet.at("in_reply_to_status_id").inner_html unless dm
      if (not reply_to.nil?) and (not reply_to.eql?(""))
        track_reply(reply_to)
      end#if reply_to
    end#if status already exists
    rescue RetrieveError => e
      puts "Couldn't download tweet #{e.reason}"
    end#begin block
  end#def save_tweet

end

