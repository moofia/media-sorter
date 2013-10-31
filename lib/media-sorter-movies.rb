# all methods which relate to movies

# process movies to see what to do with it
def process_movie(src)
  return if @movie_dir !~ /\w/
  return if src =~ /\.nfo$/i
  return if src =~ /\/subs$/i
  return if src =~ /\.sample$/i
  if $config["movies_directory"]["process"] == true
    movie = Movie.new src    
    movie.status = handle_movie_directory movie if movie.is_movie?
  end
end

# check if the file is a movie file based on the directory name
def movie_directory(directory)

  movie = ""
  $config['movies_directory']['regex'].each do |pattern|
    if directory =~ /#{pattern}/i
      movie   = $1 if $1
      return true, movie
    end
  end
  return false, movie
end

# check if the file is a movie file based on the file name
def movie_file(file)
  ext_list = $config["movies_file"]["media_extentions"].gsub(/,/,"|")
  ext = ".*\.(#{ext_list})$" 
  name = ""

  $config['movies_file']['regex'].each do |pattern|
    if file =~ /.*#{pattern}#{ext}/i
      name    = $1 if $1
      return false if name =~ /^sample/i
      return true
    end
  end
  return false
end

# wrapper method to decided which db to query
def movie_lookup(movie)
  if $config.has_key? "themoviedb" and $config["themoviedb"].has_key? "api_key" and $config["themoviedb"].has_key? "base_url"
    log("movie_lookup themoviedb: #{movie.name}") if $opt["debug"]
    themoviedb_lookup movie
  end
end

# handle the movie directory and decided what actions must be taken
def handle_movie_directory(movie)  
  log("handle_movie_directory: #{movie.directory}") if $opt["debug"]
  files = find_files(false,movie.directory)
  status = true
  files.each do |file|
    # we must first make sure its not a tv file
    tv_status, tv_show, tv_season, tv_number  = tv_file File.basename file
    if tv_status
      log ("error: #{movie.directory} contains a tv show -> #{File.basename file}")
      status = false 
    end
    if not tv_status
      # for now we only interested in if anything matches, later we can remove non movie
      # related files if we wish
      status = movie_file File.basename file if status == true
    end
  end

  if status == true
    movie.enrich
    # hmmm not too sure about this ?
    if $config["themoviedb"].has_key? "display_info_move" and $config["themoviedb"]["display_info_move"] == true
      themoviedb_display movie 
      result = handle_yes_no("move_movie","keep \"#{movie.name}\" based on the description ")
    end
    result = handle_yes_no("move_movie","movie found: move #{movie.title_full} \"#{movie.name}\"")
    if result
      move_directory(movie.directory,@movie_dir) 
    end
  else
    log("move #{movie.directory} -> contains invalid files doing nothing")    
  end
    
  status
end
