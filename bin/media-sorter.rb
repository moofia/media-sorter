#!/usr/bin/ruby

# script to src media from a storage location to @tv folder directories

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
require "#{$script_dir}/lib/media-sorter-thetvdb.rb"
require "#{$script_dir}/lib/media-sorter-themoviedb.rb"
# json rpc calls for xbmc
require "#{$script_dir}/lib/media-sorter-xbmc-module"

@script = File.basename $0 

# exit on ctrl-c
trap("INT") do
  puts
  exit 2
end 

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
    ["--new",                         Getopt::BOOLEAN],
    ["--verbose",                     Getopt::BOOLEAN],
    ["--find-missing",                Getopt::BOOLEAN],
    ["--prune-empty-directories",     Getopt::BOOLEAN],
    ["--dst",                         Getopt::OPTIONAL],
    ["--dst2",                        Getopt::OPTIONAL],
    ["--src",                         Getopt::OPTIONAL],
    ["--dst_movie",                   Getopt::OPTIONAL],
    ["--movie",                       Getopt::BOOLEAN],
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
@tvdir2        = $config["settings"]["destination_directory2"]
src            = $opt["src"] if $opt["src"]
@tvdir         = $opt["dst"] if $opt["dst"]
@tvdir2        = $opt["dst2"] if $opt["dst2"]
@src           = src
@movie_dir     = $config["settings"]["destination_movie_directory"]
@movie_dir     = $opt["dst_movie"] if $opt["dst_movie"]

$options       = {} 
$options[:noop]    = true if $opt["dry"]
$options[:verbose] = true if $opt["verbose"]
$options       = $options
@tvdb_episodes = {}
$cache_state   = false
@errors        = {}

$opt["tvdb"]   = $config["tvdb"]["default"] if not $opt["tvdb"]
$opt["dst_no_hierarchy"]  = $config["settings"]["dst_no_hierarchy"] if $config["settings"]["dst_no_hierarchy"]

$config["settings"]["log_level"] = $opt["log-level"].to_i if $opt["log-level"]

log("debug enabled",4)
log("dry run enabled, no files will be renamed or moved") if $opt["dry"]

# test to see if the filesystem is case sensitive or not for destination paths.
fs_case_sensitivity_test

# i dont like this here, move_file should be take this into account
if @tvdir2
  files_secondary = find_files(true,@tvdir2)
  @is_on_secondary_storage = is_on_secondary_storage @tvdir2,files_secondary
end

# remove trailing / from bash_completion
src = src.gsub(/\/$/,'')

# prune empty directories and exit
if $opt["prune-empty-directories"]
  remove_empty_directories(src)
  exit
end

# find missing episodes. at the moment this must exist once completed
if $opt["find-missing"]
  find_missing(files) 
  exit
end

# first we process files in the current src   
process_file(src)
  
get_directories(src).each do |directory|
  media = ""
  media = process_file(directory)
  media = process_movie(directory) if media == ""
end

# remove empty directories, only in recursive mode
if $config["settings"]["prune_empty_directories"]
  remove_empty_directories(src)
end

display_errors

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

