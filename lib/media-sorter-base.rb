# start of an include file for all common methods

# prompt, based on action delete etc
def prompt(file,action,msg)
  if not $config["settings"]["prompt_prune_duplicates"]
    print msg
    answer = STDIN.gets.chomp
    if answer =~ /^y$/i
      FileUtils.rm(file,$options) if action == "delete"
    end
  elsif $config["settings"]["auto_prune_duplicates"]
    @script = File.basename $0 
    msg.gsub!(/#{@script} -> /,'')
    msg.gsub!(/remove new .*\[y\/n\]/,'autoremove occuring')
    log msg
    FileUtils.rm(file,$options) if action == "delete"
  end
end

# facilitate debugging of an object
def debug(d)
  ap d
  puts
  exit 2
end

# generic logger
def log(msg,level=nil)
 level ||= 1
 # this line seems odd to me, not too sure what it is trying to achieve or if its working.
 return if  level > $config["settings"]["log_level"]
 
 @script = File.basename($0).split(/\./)[0] 
 FileUtils.mkdir_p("#{$script_dir}/var/log") if not File.directory? "#{$script_dir}/var/log"
 
 logfile = $script_dir + "/var/log/#{@script}.log"
 logfile = $config["settings"]["log_directory"] + "/#{@script}.log" if $config["settings"].has_key? 'log_directory'
 if $config["settings"]["log_file"]
   File.open(logfile, 'a') do |f|
     now = Time.new.strftime("%Y-%m-%d %H:%M:%S")
     f.puts "#{@script} #{now} -> #{msg}"
   end
 end
 puts "#{@script} -> #{msg}"
end

# new logger just to keep track of new files, mostly used when not using xbmc
def log_new(msg)
 @script = File.basename($0).split(/\./)[0] 
 logfile = $script_dir + "/var/log/#{@script}_new.log"
 logfile = $config["settings"]["log_directory"] + "/#{@script}_new.log" if $config["settings"].has_key? 'log_directory'
 if $config["settings"]["log_file"]
   File.open(logfile, 'a') do |f|
     now = Time.new.strftime("%Y-%m-%d %H:%M:%S")
     f.puts "#{@script} #{now} -> #{msg}"
   end
 end
 puts "#{@script} -> #{msg}"
end

# check if the file is a tv file based on the file name
def tv_file(file)
  ext_list = $config["series"]["media_extentions"].split(/,/).map.join("|")
  ext = ".*\.(#{ext_list})$" 
  name, season, episode = "", "", ""

  $config['series']['regex'].each do |pattern|
    if file =~ /#{pattern}#{ext}/i
      name    = $1 if $1
      season  = $2 if $2
      episode = $3 if $3
      return true, name, season, episode
    end
  end
  return false, name, season, episode
end

# clean up , not really being used at the moment.
# idea is to remove previous directories that are empty once sorting is completed.
def clean_up(sort)
  log("cleanining up : #{sort}")
  Find.find(sort) do |path|
    next if not File.directory? path
    next if not Dir["#{path}/.*"].empty?
    #FileUtils.rmdir(path,$options)
    FileUtils.rmdir(path)
  end
end

# returns an array of tv files
def find_files(recusive,sort)
  ext_list = $config["series"]["media_extentions"].split(/,/).map.join("|")
  files = []
  Find.find(sort) do |path|
    next if File.dirname(path) != sort and not recusive
    next if File.directory? path
    next if File.basename(path) =~ /^\./
    #status, name, season, episode  =  tv_file File.basename(path)
    #next if not status
    next if path !~ /#{ext_list}$/
    files << path
  end
  files
end

# returns an array of files that are not tv files
def find_files_not(sort)
  files = []
  Find.find(sort) do |path|
    next if File.directory? path
    next if File.basename(path) =~ /^\./
    next if (tv_file File.basename(path))
    files << path
  end
  files
end

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

  edit #{File.dirname($0)}/etc/media-sorter.yaml for more options
  
HELP

exit
end

# returns a xml of the url to get via a proxy
def xml_get_via_proxy(url)
  log("http get via proxy : #{url}") if $opt["debug"]
  begin
    proxy = ENV['http_proxy']
    proxy_host, proxy_port = proxy.gsub(/^http:\/\//,'').split(/:/)
    myurl = URI.parse(url)
    req = Net::HTTP::Get.new(myurl.request_uri)
    res= Net::HTTP::Proxy(proxy_host, proxy_port).start(myurl.host,myurl.port) { |http| http.request(req) }
    html = res.body
  # XXX must fix the rescue its not working
  rescue => err
    log("Error: #{err}")
    exit 2
  end
  html
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
  cache_dir = $script_dir + "/var/tvdb/" + show
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + show if $config["tvdb"].has_key? "cache_directory"
  
  FileUtils.mkdir_p(cache_dir) if not File.directory? cache_dir
  cache = cache_dir + "/" + show + ".xml"
  if File.exists? cache and not $opt["tvdb-refresh"]
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show id : #{show}")
    show_escaped = CGI.escape(show)
    url = $config["tvdb"]["mirror"] + '/api/GetSeries.php?&language=en&seriesname=' + show_escaped
    if ENV.has_key? "http_proxy"
      xml_data = xml_get_via_proxy(url)
    else
      xml_data = xml_get(url)      
    end
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
  cache_dir = $script_dir + "/var/tvdb/" + show
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + show if $config["tvdb"].has_key? "cache_directory"
  cache = cache_dir + "/" + show_id + ".xml"
  if File.exists? cache and not $opt["tvdb-refresh"]
    log("tvdb retrieving show episodes via cache: #{show} (#{show_id})")
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show episodes via www: #{show} (#{show_id})")
    url = $config["tvdb"]["mirror"] + '/api/' + $config["tvdb"]["api_key"] + '/series/' + show_id + '/all/en.xml'
    if ENV.has_key? "http_proxy"
      xml_data = xml_get_via_proxy(url)
    else
      xml_data = xml_get(url)      
    end
    parser = XML::Parser.string xml_data
    doc = parser.parse
    File.open(cache, 'w') do |file|
      xml_data.each {|x| file.puts x}
    end
  end

  doc.find('//Data/Episode').each do |item| 
   season  = item.find('SeasonNumber')[0].child.to_s
   episode = item.find('EpisodeNumber')[0].child.to_s
   name    = item.find('EpisodeName')[0].child.to_s
   episodes[show] = Hash.new unless episodes[show].class == Hash
   episodes[show][season] = Hash.new unless episodes[show][season].class == Hash
   episodes[show][season][episode] = name
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
 if stats["src_size"] < 100000000 and $config["settings"]["prune_small"]
   msg = "#{@script} -> src file less than 100M: \'#{File.basename(f) }\' remove new file ? [y/n] "
   prompt(f,"delete", msg)
   return 2
 end
 
 if File.exists? "#{target}/#{File.basename(f)}"
   log("warning dst file exists: \'#{File.basename(f)}\'",2) if $config["settings"]["log_level"] > 2
   if stats["src_size"] == stats["dst_size"] and $config["settings"]["prompt_prune_duplicates"] and f != target_file
     msg = "#{@script} -> duplicate equal size: \'#{File.basename(f) }\' remove new copy ? [y/n] "
     prompt(f,"delete",msg)
     return 2
   elsif stats["src_size"] != stats["dst_size"] and f != target_file
     msg = "duplicate: src \'#{f}\' (#{stats["src_size"]}) -> dst \'#{target_file}\' (#{stats["dst_size"]}) fix manually"
     #prompt(f,"delete",msg)
     log msg
   else
     log "warning src and dst equal for '#{File.basename(f)}\' with auto pruning enable, doing nothing"
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
    return false
  end
  re_cache = episode.fix_via_tvdb @tvdb_episodes if $opt["tvdb"] and @tvdb_episodes.has_key?(episode.show)
  
  # we do one round of re-caching only if the episode name is not found
  if not re_cache 
    log("re-caching from tvdb")
    $opt["tvdb-refresh"] = true
    @tvdb_episodes = {}
    tvdb_result = tvdb(episode.show) if ($opt["tvdb"]) && (! @tvdb_episodes.has_key?(episode.show))
    if tvdb_result == false
      log("failed to find tvshow \'#{episode.show}\' from tvdb, skipping..")
      return false
    end
    episode.fix_via_tvdb @tvdb_episodes if $opt["tvdb"] and @tvdb_episodes.has_key?(episode.show)
  end
  
  season_pre = "season."
  season_pre = $config["settings"]["season_dir_prepend"] if $config["settings"].has_key? "season_dir_prepend"
  season = "#{season_pre}#{episode.season}"
  season = "specials" if episode.season == "0"
  target = "#{@tvdir}/#{episode.show}/#{season}"  
  target = "#{@tvdir}" if $opt["dst_no_hierarchy"]
  move_file(episode.file,target)
end
