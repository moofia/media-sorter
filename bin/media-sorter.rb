#!/usr/bin/ruby

# script to src media from a storage location to @tv folder directories

# dependancies
#
#
# gem install awesome_print
# gem install titlecase
# gem install getopt
# gem install json

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

$script_dir = File.expand_path($0).gsub(/\/bin\/.*/,'')

# main include file for the script
require "#{$script_dir}/lib/media-sorter-base"
require "#{$script_dir}/lib/media-sorter-classes"
# json rpc calls
require "#{$script_dir}/lib/media-sorter-xbmc-module"

@script = File.basename $0 

# options 
begin
  $opt = Getopt::Long.getopts(
    ["--debug",                       Getopt::BOOLEAN],
    ["--help",                        Getopt::BOOLEAN],
    ["--dst_no_hierarchy",            Getopt::BOOLEAN],
    ["--recursive",                   Getopt::BOOLEAN],
    ["--tvdb",                        Getopt::BOOLEAN],
    ["--tvdb-refresh",                Getopt::BOOLEAN],
    ["--dry",                         Getopt::BOOLEAN],
    ["--find-missing",                Getopt::BOOLEAN],
    ["--prune-empty-directories",     Getopt::BOOLEAN],
    ["--dst",                         Getopt::OPTIONAL],
    ["--src",                         Getopt::OPTIONAL],
    ["--log-level",                   Getopt::OPTIONAL]
    )
rescue Getopt::Long::Error => e
  puts "#{@script} -> error #{e.message}"  
  puts 
  help
end

help if $opt["help"]

$config        = YAML::load(File.read("#{$script_dir}/etc/media-sorter.yaml"))
$config_rename = YAML::load(File.read("#{$script_dir}/etc/tv-name-mapping.yaml"))
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

# prune empty directories and exit
if $opt["prune-empty-directories"]
  remove_empty_directories(src)
  exit
end

# find all files
log("recursive src") if $opt["recursive"]
files = find_files($opt["recursive"],src)

# find missing episodes. at the moment this must exist once completed
if $opt["find-missing"]
  find_missing(files) 
  exit
end

# loop through list of files looking for media, if its a tv episode proceed to 
# move the file to the correct location, this includes renaming to correct syntax
# if desired
files.each do |file|
  log("found #{file}",4)
  episode = Episode.new file
  episode.status = look_and_mv episode if episode.is_ep?  
end

# remove empty directories
if $config["settings"]["prune_empty_directories"]
  remove_empty_directories(src)
end

puts

# see which media files were found but failed to an episode that we expected 
@new_media = false
Episode.find_all.each do |e|
  log("error: not a recognized episode #{e.file}") if not e.is_ep?
  @new_media = true if e.is_ep?
end

if $config["http_rpc"]["update_library"]
  # scan for new content
  ap XBMC.scan_for_content if @new_media

  print "#{@script} -> press enter to continue "
  STDIN.gets
  
  results = XBMC.get_recently_added_episodes
  puts
  results["result"]["episodes"].each do |e|
    ep = e["file"].split('/')
    puts ep[ep.length - 1]
  end

end

