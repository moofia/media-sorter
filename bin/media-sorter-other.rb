#!/usr/bin/ruby

# script to src media from a storage location to @tv folder directories

# dependancies
# gem install awesome_print
# gem install titlecase
# gem install getopt

# TODO: tvdb cache does not refresh
# TODO: tvdb api requests that one respects the future use of mirrors, must implement
# TODO: Show class ?? not sure if i would gain anything by this, might mask tvdb totally though which will be good
# TODO: find files that are not named correctly
# TODO: require search path ?

require 'rubygems'
require 'ap'
require 'fileutils'
require 'getopt/long'
require 'find'
require 'net/http'
require 'xml/libxml'
require 'cgi'
require 'yaml'
require 'titlecase'
require 'json'

# main include file for the script
require 'media-require'

# json rpc calls
require 'xbmc-json-rpc'

@script = File.basename $0 

# basic help
def help
  @script = File.basename $0 
puts <<HELP
  usage: #{@script} --src [src dir] --dst [destination dir] --debug

  --src               source folder
  --dst               destination folder
  --dst_no_hierarchy  destination folder hierarchy off
  --debug             extra log messages for debugging
  --recursive         recurse directory tree
  --tvdb              correct filename based on tvdb
  --tvdb-refresh      force a refresh of tvdb content (warning applies globally)
  --dry               dryrun, no files are renamed / removed
  --log-level         log level

  --help

HELP

exit
end

# options 
begin
  $opt = Getopt::Long.getopts(
    ["--debug",            Getopt::BOOLEAN],
    ["--help",             Getopt::BOOLEAN],
    ["--dst_no_hierarchy", Getopt::BOOLEAN],
    ["--recursive",        Getopt::BOOLEAN],
    ["--tvdb",             Getopt::BOOLEAN],
    ["--tvdb-refresh",     Getopt::BOOLEAN],
    ["--dry",              Getopt::BOOLEAN],
    ["--dst",              Getopt::OPTIONAL],
    ["--src",              Getopt::OPTIONAL],
    ["--log-level",        Getopt::OPTIONAL]
    )
rescue Getopt::Long::Error => e
  puts "#{@script} -> error #{e.message}"  
  puts 
  help
end

# returns a xml of the url to get.
def xml_get(url)
  log("http get : #{url}") if $opt["debug"]
  begin
    html = Net::HTTP.get_response(URI.parse(url)).body
  # XXX must fix the rescue its not working
  rescue => err
    log("Error: #{err}")
    exit 2
  end
  html
end

# query thetvdb.com to get the show id.
def get_show_id(show)
  show_id = ""
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + show
  FileUtils.mkdir_p(cache_dir) if not File.directory? cache_dir
  cache = cache_dir + "/" + show + ".xml"
  if File.exists? cache and not $opt["tvdb-refresh"]
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show id : #{show}")
    show_escaped = CGI.escape(show)
    url = $config["tvdb"]["mirror"] + '/api/GetSeries.php?&language=en&seriesname=' + show_escaped
    xml_data = xml_get(url)
    parser = XML::Parser.string xml_data
    doc = parser.parse
    File.open(cache, 'w') do |file| 
      xml_data.each {|x| file.puts x}
    end
  end
  doc.find('//Data/Series').each do |item|
    find = show
    find = Regexp.escape(show) if show =~ /\'|\(|\&/
    series_name = item.find('SeriesName')[0].child.to_s
    series_name = CGI.unescapeHTML(series_name)
    pre_regex = '^'
    
    # having a problem matching some shows due to the colon issue above not being able to be used in a filename on fat32
    pre_regex = '' if series_name =~ /:/
    # file names can not contain ':' so we need to remove them from possible show names
    series_name.gsub!(/:/,'')
    find.gsub!(/:/,'')

    if series_name  =~ /#{pre_regex}#{find}$/i     
       show_id = item.find('id')[0].child.to_s
    end
  end
  if show_id == ""
   log("tvdb error: can not find id for show \'#{show}\'")
   show_id = false
  end
  show_id
end

# query thetvdb.com to get the episodes of the show, right now this is cached but one will have to look
# the time stamps to know when to fetch new data.
def get_show_episodes(show_id,show)
  episodes = {}
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + show
  cache = cache_dir + "/" + show_id + ".xml"
  if File.exists? cache and not $opt["tvdb-refresh"]
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show episodes : #{show} (#{show_id})")
    url = $config["tvdb"]["mirror"] + '/api/' + $config["tvdb"]["api_key"] + '/series/' + show_id + '/all/en.xml'
    xml_data = xml_get(url)
    parser = XML::Parser.string xml_data
    doc = parser.parse
    File.open(cache, 'w') do |file|
      xml_data.each {|x| file.puts x}
    end
  end

  doc.find('//Data/Episode').each do |item| 
   season      = item.find('SeasonNumber')[0].child.to_s
   episode     = item.find('EpisodeNumber')[0].child.to_s
   name        = item.find('EpisodeName')[0].child.to_s
   first_aired = item.find('FirstAired')[0].child.to_s
   episodes[show] = Hash.new unless episodes[show].class == Hash
   episodes[show][season] = Hash.new unless episodes[show][season].class == Hash
   episodes[show][season][episode] = Hash.new unless episodes[show][season][episode].class == Hash
   episodes[show][season][episode][name] = Hash.new unless episodes[show][season][episode][name].class == Hash
   episodes[show][season][episode][name]["first_aired"] = first_aired
  end
  episodes
end

# moves the file to target location and creates directories if needed
def move_file(f,target)
 target_file = target + "/" + File.basename(f)   
 stats = {}
 stats["src_size"] = ( not File.size?(f).nil?) ? File.size?(f) : 0
 stats["dst_size"] = ( not File.size?(target_file).nil? ) ? File.size?(target_file) : 0
 
 if stats["src_size"] == 0 
   msg = "#{@script} -> src file zero bytes: \'#{File.basename(f) }\' remove new file ? [y/n] "
   prompt(f,"delete",msg)
   return 2
 end
 if stats["src_size"] < 100000000
   msg = "#{@script} -> src file less than 100M: \'#{File.basename(f) }\' remove new file ? [y/n] "
   prompt(f,"delete", msg)
   return 2
 end
 
 if File.exists? "#{target}/#{File.basename(f)}"
   log("warning dst file exists: \'#{File.basename(f)}\'",2) if 2 == $config["settings"]["log_level"]
   
   if stats["src_size"] == stats["dst_size"] and $config["settings"]["prompt_prune_duplicates"]
     msg = "#{@script} -> duplicate equal size: \'#{File.basename(f) }\' remove new copy ? [y/n] "
     prompt(f,"delete",msg)
     return 2
   end
   
   if $config["settings"]["log_level"] > 2
     if stats["src_size"] == stats["dst_size"]
       log "warning duplicate equal size: src \'#{f}\' -> dst \'#{target_file}\'"
       # should be safe to save some time here and prompt to ask if one wishes to remove src file
     else
       log "warning duplicate: src \'#{f}\' (#{stats["src_size"]}) -> dst \'#{target_file}\' (#{stats["dst_size"]})"
     end
   end
   return 2
 end
 # if the directory does not exist it is created
 FileUtils.mkdir_p(target,$options) if not File.directory? target
 FileUtils.mv(f,target,$options) if ( (File.dirname f) != target.gsub(/\/$/,'')) 
 log_new("#{File.basename(f) }")
 1
end

def tvdb(show)
  show_id = get_show_id(show)
  @tvdb_episodes = get_show_episodes(show_id,show) if show_id     
  return false if show_id == false
end

def look_and_mv(episode)
  tvdb_result = tvdb(episode.show) if ($opt["tvdb"]) && (! @tvdb_episodes.has_key?(episode.show))
  if tvdb_result == false
    log("failed to find tvshow \'#{episode.show}\' from tvdb, skipping..")
    return 2
  end
  episode.fix_via_tvdb @tvdb_episodes if $opt["tvdb"] and @tvdb_episodes.has_key?(episode.show)
  season = "season.#{episode.season}"
  season = "specials" if episode.season == "0"
  target = "#{@tvdir}/#{episode.show}/#{season}"  
  target = "#{@tvdir}" if $opt["dst_no_hierarchy"]
  move_file(episode.file,target)
end

def json_rpc

# update library
host = "192.168.0.15"

log("updating video library @#{host}")

exit 2
#cmd ="curl -s -H \"Content-Type: application/json\" http://#{host}:8080/jsonrpc --data-binary \'{\"jsonrpc\":\"2.0\",\"method\":\"VideoLibrary.ScanForContent\",\"id\":1}\'"
#log cmd
#{}`#{cmd}`

json = <<-JSON
{"jsonrpc":"2.0","method":"VideoPlayer.PlayPause","id":1}
JSON

uri = "/jsonrpc"
request = Net::HTTP::Post.new(uri)
request["content-type"] = "application/json"
request.body = json

response = Net::HTTP.start(host, "8080") { |http|http.request(request) }

  unless response.kind_of?(Net::HTTPSuccess)
    debug response
  end
puts response.body
result = JSON.parse(response.body)
puts result.inspect

end

## main 
##

help if $opt["help"]

$config        = YAML::load(File.read("#{File.dirname($0)}/media-sorter-renamer.yaml"))
src            = $config["settings"]["source_directory"]
@tvdir         = $config["settings"]["destination_directory"]
src            = $opt["src"] if $opt["src"]
@tvdir         = $opt["dst"] if $opt["dst"]
$options       = {:verbose=> true} 
$options       = {:noop=>true,:verbose=> true} if $opt["dry"]
$options       = $options
@tvdb_episodes = {}

$opt["tvdb"]   = $config["tvdb"]["default"] if not $opt["tvdb"]
$opt["dst_no_hierarchy"]  = $config["settings"]["dst_no_hierarchy"] if $config["settings"]["dst_no_hierarchy"]

$config["settings"]["log_level"] = $opt["log-level"].to_i if $opt["log-level"]

log("debug enabled",4)
log("dry run enabled, no files will be renamed or moved") if $opt["dry"]

# remove trailing / from bash_completion
src = src.gsub(/\/$/,'')

# find all files
log("recursive src") if $opt["recursive"]
files = find_files($opt["recursive"],src)

eps = {}

# loop through list of files looking for media
files.each do |file|
  next if not file[/.*\/(.*)\/season.*\/.*\s\[(\d+)x(\d+)\]\s(.*)/i]
  show = $1
  season = $2
  number = $3.to_i.to_s
  eps[show]                 = {} if eps[show].class.to_s != 'Hash'
  eps[show][season]         = {} if eps[show][season].class.to_s != 'Hash'
  eps[show][season][number] = file
  
  if ($opt["tvdb"]) and ! eps[show].has_key? "tvdb"
    tvdb_result = tvdb(show)
    if tvdb_result == false 
      log("failed to find tvshow \'#{show}\' from tvdb, skipping..")
    else
      max = @tvdb_episodes[show][season].max[0]
      tmp_date = "2020-01-01"
      @tvdb_episodes[show][season][max].keys.each do |name|
        tmp_date = @tvdb_episodes[show][season][max][name]["first_aired"] if @tvdb_episodes[show][season][max][name].has_key? "first_aired"
        end
        
      yyyy, mm, dd = $1, $2, $3 if tmp_date =~ /(\d+)-(\d+)-(\d+)/
      if Time.mktime(yyyy, mm, dd) < Time.now.localtime
        eps[show]["tvdb"] = Hash.new unless eps[show]["tvdb"].class == Hash
        eps[show]["tvdb"][season] = Hash.new unless eps[show]["tvdb"][season].class == Hash
        eps[show]["tvdb"][season]["max"] = max
      end
    end
  end
end

eps.keys.each do |show|
  eps[show].keys.each do |season|
    next if season == "tvdb"
    max = eps[show][season].max[0]
    max = eps[show]["tvdb"][season]["max"] if eps[show]["tvdb"].has_key? season

   # max = eps[show]
    eps[show][season].min[0].upto(max) do |i|
      # found a missing episode, for now just display something
      log("missing: #{show} season #{season} -> number #{i}") if not eps[show][season].has_key? i
      end
    end
  end    
