require 'rubygems'
require 'tmpdir'
require 'optparse'
require 'rexml/document'
require 'fileutils'
require 'builder'

# given an array of texts, return a hash of the number of times each 
# word appears
def concordance(texts)
  count = Hash.new(0)
  texts.each do |text|
    text.split.each do |word|
      count[word] = count[word] + 1
    end
  end
  return count
end

# boil a tweet down to its least common words
def summarize(text, concordances)
  return text
end

$options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: timeline.rb -u USERNAME"
  
  opts.on("-u", "--user USERNAME", String, "Username") { |u| $options[:user] = u}
end.parse!

if [:user].map {|opt| $options[opt].nil?}.include?(nil)
  puts "Usage: timeline.rb -u USERNAME"
  exit
end

statuses_xml = File.join(Dir::tmpdir, "#{$options[:user]}.xml")

system("SCREEN_NAME=#{$options[:user]} ./cat_statuses.sh > #{statuses_xml}")

xml = File.new(statuses_xml)
doc = REXML::Document.new(xml)

texts = []

REXML::XPath.each(doc, "//text") {|element| texts << element.text}

xml.close

concordances = concordance(texts)

# make timeline data for SIMILE
FileUtils.mkdir_p('timelines')

timeline_file = File.join('timelines', "#{$options[:user]}_events.xml")

File.open(timeline_file, "w") do |timeline|
  xml = File.new(statuses_xml)
  doc = REXML::Document.new(xml)
  builder = Builder::XmlMarkup.new(:indent => 1)
  builder.instruct!
  data = builder.data do |b|
    REXML::XPath.each(doc, "statuses/status") do |status|
      text = status.elements['text'].text
      builder.event( text,
                    :start => status.elements['created_at'].text,
                    :title => summarize(text, concordances))
    end
  end
  timeline.write(data)
end




