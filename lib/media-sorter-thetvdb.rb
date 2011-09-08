# http://www.thetvdb.com/

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
    find = Regexp.escape(show) if show =~ /\'|\(|\&|\*/
    
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
   log("tvdb error: can not find id for show \'#{show}\'")
   show_id = false
  end
  show_id
end

# query thetvdb.com to get the episodes of the show, right now this is cached but one will have to look
# the time stamps to know when to fetch new data.
def get_show_episodes(show_id,show)
  episodes = {}
  local_file = show.gsub(/\*/,'_')
  cache_dir = $script_dir + "/var/tvdb/" + local_file
  cache_dir = $config["tvdb"]["cache_directory"] + "/" + local_file if $config["tvdb"].has_key? "cache_directory"
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

  #series_name = show
  
  #doc.find('//Data/Series').each do |item|
  #  series_name  = item.find('SeriesName')[0].child.to_s
  #end

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

def tvdb(show)
  show_id = get_show_id(show)
  @tvdb_episodes = get_show_episodes(show_id,show) if show_id     
  return false if show_id == false
  true
end

