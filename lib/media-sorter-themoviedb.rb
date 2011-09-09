# http://www.themoviedb.org

# first call for a lookup, only returns a new name of the movie and a status
def themoviedb_lookup(movie)
  log ("themoviedb_lookup: #{movie.name}")
  state = false
  themoviedb_auth
  state, new_name, movie_full = themoviedb_movie_search movie.name
  movie.name = new_name
  movie.enrich_movie_full = movie_full
  movie.enrich_status = state
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
  
  # dont have a valid api key yet so just return true all the time.
  #return true, name , "The Earth is caught in the middle of an intergalactic war between two races of robots,objects, including cars, trucks, planes and other technological creations."
  
  state = false
  puts 
  url = themoviedb_build_url("Transformers","search")
  result =  http_get(url)
  json_result = JSON.parse(result)
  state, movie_full = themoviedb_movie_search_parse_json(json_result)
  
  log("themoviedb_movie_search: update object")
  
  new_name = name
  return state, new_name, movie_full
end

# http://api.themoviedb.org/2.1/methods/Movie.getInfo
# Movie.getInfo
# The Movie.getInfo method is used to retrieve specific information about a movie. 
# Things like overview, release date, cast data, genre's, YouTube trailer link, etc...
def themoviedb_movie_getInfo(name)
  log("themoviedb_movie_getInfo: #{name}")
end

# default data returned is json, parse it
def themoviedb_movie_search_parse_json(json_data)
  log("themoviedb_movie_search: json_data")
  ap json_data if $opt["debug"]
  return true, "The Earth is caught in the middle of an intergalactic war between two races of robots,objects, including cars, trucks, planes and other technological creations."
end

def themoviedb_build_url(name,method)
  log("themoviedb_build_url")
  name_escaped = CGI.escape(name)
  
  if method == "search"
    url = "#{$config["themoviedb"]["base_url"]}/Movie.search/en/xml/#{$config["themoviedb"]["api_key"]}/#{name_escaped}"
  end
  url
end

# display retrieved data
def themoviedb_display(movie)
  if movie.enrich_status == true
    ap movie
  end
end

#### new html methods, will be moved elsewhere later
