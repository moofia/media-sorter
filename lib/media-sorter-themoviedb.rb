# http://www.themoviedb.org

# first call for a lookup, only returns a new name of the movie and a status
def themoviedb_lookup(name)
  log ("themoviedb_lookup: #{name}")
  return
  state = false
  themoviedb_auth
  state, new_name = themoviedb_movie_search name
  
  return state, new_name
end

# ? not sure if needed for readonly
def themoviedb_auth
  log("themoviedb_auth")
end

# http://api.themoviedb.org/2.1/methods/Movie.search
# Movie.search
# The Movie.search method is the easiest and quickest way to search for a movie. 
# It is a mandatory method in order to get the movie id to pass to (as an example) the Movie.getInfo method.
def themoviedb_movie_search(name)
  log("themoviedb_movie_search: #{name}")
  state = false
  puts 
  url = themoviedb_build_url("Transformers","search")
  result =  http_get_xml(url)
  json_result = JSON.parse(result)
  themoviedb_movie_search_parse_json(json_result)
  
  log("themoviedb_movie_search: update object")
  
  debug("forced exit in themoviedb_movie_search")
  new_name = name
  return state, new_name
end

# http://api.themoviedb.org/2.1/methods/Movie.getInfo
# Movie.getInfo
# The Movie.getInfo method is used to retrieve specific information about a movie. 
# Things like overview, release date, cast data, genre's, YouTube trailer link, etc...
def themoviedb_movie_getInfo(name)
  log("themoviedb_movie_getInfo: #{name}")
end

def themoviedb_movie_search_parse_json(json_data)
  log("themoviedb_movie_search: json_data")
  debug json_data
end

def themoviedb_build_url(name,method)
  log("themoviedb_build_url")
  name_escaped = CGI.escape(name)
  
  if method == "search"
    url = "#{$config["themoviedb"]["base_url"]}/Movie.search/en/xml/#{$config["themoviedb"]["api_key"]}/#{name_escaped}"
  end
  url
end

#### new html methods, will be moved elsewhere later

# returns a xml of the url to get via a proxy
def http_get_xml_via_proxy(url)
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

# returns a xml of the url to gets directly
def http_get_xml_direct(url)
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

# handle http gets
def http_get_xml(url)
  if ENV.has_key? "http_proxy"
    xml_data = http_get_xml_via_proxy(url)
  else
    xml_data = http_get_xml_direct(url)      
  end
  xml_data
end