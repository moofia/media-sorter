# http://www.thetvdb.com/
# http://www.thetvdb.com/wiki/index.php/Programmers_API

# needs massive refactoring!

# query thetvdb.com to get the show id.
def thetvdb_get_show_id(show)
  # so confused why this is here suddenly!
  show.gsub!(/:/,'')
  local_file = show.gsub(/\*/,'_')
  
  show_id = ""
  cache_dir = $script_dir + "/var/tvdb/" + local_file
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + local_file if $config["tvdb"].has_key? "cache_directory"

  
  FileUtils.mkdir_p(cache_dir) if not File.directory? cache_dir
  cache = cache_dir + "/" + show + ".xml"
  if File.exists? cache and not $opt["tvdb-refresh"]
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show id via www: #{show}")
    show_escaped = CGI.escape(show)
    url = $config["tvdb"]["mirror"] + '/api/GetSeries.php?&language=en&seriesname=' + show_escaped
    xml_data =  http_get(url)
    #if ENV.has_key? "http_proxy"
    #  xml_data = xml_get_via_proxy(url)
    #else
    #  xml_data = xml_get(url)      
    #end
    parser = XML::Parser.string xml_data
    doc = parser.parse
    File.open(cache, 'w') do |file| 
      xml_data.each {|x| file.puts x}
    end
  end
  doc.find('//Data/Series').each do |item|
    find = show
    find = Regexp.escape(show) if show =~ /\'|\(|\&|\*|\?/
    
    series_name = item.find('SeriesName')[0].child.to_s
    series_name = CGI.unescapeHTML(series_name)
    pre_regex = '^'
    
    # having a problem matching some shows due to the colon issue above not being able to be used in a filename on fat32
    # this si being commented out as its not working
    #pre_regex = '' if series_name =~ /:/
    # file names can not contain ':' so we need to remove them from possible show names
    series_name.gsub!(/:/,'')
    find.gsub!(/:/,'')

    if series_name  =~ /#{pre_regex}#{find}$/i     
       show_id = item.find('id')[0].child.to_s
    end
  end
  if show_id == ""
   handle_error("tvdb error: can not find id for show \'#{show}\'")
   show_id = false
  end
  show_id
end

# query thetvdb.com to get the episodes of the show, right now this is cached but one will have to look
# the time stamps to know when to fetch new data.
def thetvdb_get_show_episodes(show_id,show)
  episodes = {}
  local_file = show.gsub(/\*/,'_')
  cache_dir = $script_dir + "/var/tvdb/" + local_file
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + local_file if $config["tvdb"].has_key? "cache_directory"
  cache = cache_dir + "/" + show_id + ".xml"
  
  if File.exists? cache and not $opt["tvdb-refresh"]
    log("tvdb retrieving show episodes via cache: #{show} (#{show_id})") if $opt["debug"]
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show episodes via www: #{show} (#{show_id})") if $opt["debug"]
    url = $config["tvdb"]["mirror"] + '/api/' + $config["tvdb"]["api_key"] + '/series/' + show_id + '/all/en.xml'
    xml_data =  http_get(url)
  
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
   #episodes[show]["series name"] = series_name
   episodes[show][season] = Hash.new unless episodes[show][season].class == Hash
   episodes[show][season][episode] = name
  end
  episodes
end

def thetvdb_lookup(show)
  show_id = thetvdb_get_show_id(show)
  @tvdb_episodes = thetvdb_get_show_episodes(show_id,show) if show_id     
  return false if show_id == false
  true
end

