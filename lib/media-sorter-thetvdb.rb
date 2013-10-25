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
    begin
      doc = parser.parse
    rescue => err
      log("tvdb error: #{err} when retrieving \'#{show}\'")
      return 
    end
  else
    log("tvdb retrieving show id via www: #{show}") if $config["settings"]["log_level"] > 1
    show_escaped = CGI.escape(show)
    url = $config["tvdb"]["mirror"] + '/api/GetSeries.php?&language=en&seriesname=' + show_escaped
    xml_data =  http_get(url)
    parser = XML::Parser.string xml_data
    begin
      doc = parser.parse
    rescue => err
      log("tvdb error: #{err} when retrieving \'#{show}\'")
      return 
    end
    File.open(cache, 'w') do |file| 
      file.puts xml_data
      #xml_data.each {|x| file.puts x}
    end
  end
  showIncorrectStatus = false
  
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

    log "show -> #{show} : looking at show of -> #{series_name}" if $config["settings"]["log_level"] > 1

    if series_name  =~ /#{pre_regex}#{find}$/i     
       show_id = item.find('id')[0].child.to_s
       showIncorrectStatus = false       
    end

    if show_id == ""
      showIncorrectStatus = true
    end

    if showIncorrectStatus == true
      newShow = "#{find}"
      newShow.gsub!(/(\s|\.)(us)$/i,' (us)')
      newShow.gsub!(/(\s|\.)(uk)$/i,' (uk)')
      handle_error("tvdb error: show \'#{show}\' is actually \'#{newShow}\' update tv-name-mapping.yaml")
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
    log("tvdb retrieving show episodes via cache: #{show} (#{show_id})") if $config["settings"]["log_level"] > 1
    parser = XML::Parser.file cache
    doc = parser.parse
  else
    log("tvdb retrieving show episodes via www: #{show} (#{show_id})") if $config["settings"]["log_level"] > 1
    url = $config["tvdb"]["mirror"] + '/api/' + $config["tvdb"]["api_key"] + '/series/' + show_id + '/all/en.xml'
    xml_data =  http_get(url)
  
    parser = XML::Parser.string xml_data
    doc = parser.parse
    
    File.open(cache, 'w') do |file|
      # TODO: odd no idea whats changed here or why
      file.puts xml_data
      #xml_data.split(/\n/).each {|x| file.puts x}
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
  log "show -> #{show} : show_id status -> #{show_id}" if $config["settings"]["log_level"] > 1
  @tvdb_episodes = thetvdb_get_show_episodes(show_id,show) if show_id     
  return false if show_id == false
  true
end

