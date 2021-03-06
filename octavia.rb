require 'sinatra'
require 'sinatra/flash'
require 'data_mapper'
require 'taglib'
require 'lastfm'
require 'yaml'
require 'xmlsimple'
require 'rufus/scheduler'

# DataMapper::Logger.new(STDOUT, :debug)a
$WD = File.dirname(__FILE__)
if $WD == '.'
  $WD = Dir.pwd
end
DataMapper.setup :default, "sqlite3://#{File.join($WD, 'data.db')}"

if not Dir.exists?(File.join($WD, 'files'))
  Dir.mkdir(File.join($WD, 'files'))
end

APP_SETTINGS = YAML.load(File.open(File.join(File.dirname(__FILE__), 'app.yml')))

$LAST_FM = Lastfm.new(APP_SETTINGS['lastfm']['key'], APP_SETTINGS['lastfm']['secret'])
$LAST_FM_TOKEN = $LAST_FM.auth.get_token

configure do
  enable :static
  use Rack::Session::Cookie, :secret => APP_SETTINGS['session']['secret']
end

set :protection, :except => :session_hijacking
use Rack::Logger

class Track
  include DataMapper::Resource
  property :id,             Serial
  property :title,          String, :length => 1024
  property :artist,         String, :length => 1024
  property :album,          String, :length => 1024
  property :artwork,        String, :length => 255
  property :path,           String, :length => 255
  property :buylink,        String, :length => 255
  property :deleted,        Boolean, :default => false
  property :date_uploaded,  DateTime
  property :delete_key,     String
  property :plays,          Integer, :default => 0
end

class Lastfm::MethodCategory::Track
  regular_method :get_buylinks, [:artist, :track, :country], [[:mbid, nil]] do |response|
    response.xml['affiliations']
  end
end

def scavenge_tracks
  old_tracks = Track.all :date_uploaded.lt => (Time.now - 60 * 60 * 24 * 30) # tracks > 30 days old
  old_tracks.each do |track|
    begin
      FileUtils.rm(File.join('files', File.basename(track.path))) if track.path
    rescue Errno::ENOENT
    end
    track.path = nil
    if not track.buylink
      track.buylink = lastfm_get_buylink(track.artist, track.title)
    end
    track.save
  end
end

helpers do
  def lastfm_get_artwork(artist, album)
    begin
      info = $LAST_FM.album.get_info artist, album
    rescue Lastfm::ApiError
      return "/img/artwork_missing.png"
    end

    return "/img/artwork_missing.png" if info['image'].empty?

    image_uri = info['image'].select {|i| i['content'] && i['size'] == 'extralarge' }.first || info['image'][0]
    image_uri = image_uri['content']
    return "/img/artwork_missing.png" if image_uri.nil? || image_uri.empty?
    image_uri.strip!

    image_name = "#{artist}-#{album}.png".gsub(/[^a-zA-Z0-9_\.]/, '-')
    image_path = File.expand_path(File.join('public', 'album_art', image_name))
    if system('wget', '-O', image_path, image_uri)
      "/album_art/#{image_name}"
    else
      "/img/artwork_missing.png"
    end
  end

  def generate_delete_key
    ('a'..'z').to_a.shuffle[0,8].join
  end

  def track_album_art_filename(track)
    "#{track.artist}-#{track.album}.png".gsub(/[^a-zA-Z0-9_\.]/, '-')
  end

  def protected!
      unless authorized?
        response['WWW-Authenticate'] = %(Basic realm="octavia v0.3")
        throw :halt, [401, "Not authorized\n"]
      end
  end

  def authorized?
      authorized = YAML::load(IO.read(File.join(File.dirname(__FILE__), 'auth.yml')))
      @auth ||= Rack::Auth::Basic::Request.new(request.env)
      valid = @auth.provided? && @auth.basic? && @auth.credentials && authorized.include?(@auth.credentials[0])
      valid && authorized[@auth.credentials[0]] == @auth.credentials[1]
  end

  def lastfm_get_buylink(artist, title)
    begin
      links = $LAST_FM.track.get_buylinks :artist => artist, :track => title, :country => 'United States'
    rescue Lastfm::ApiError
      return nil
    end
    buylinks = {}
    links['downloads']['affiliation'].each do |affiliate|
        if ['Amazon MP3', 'iTunes'].include? affiliate['supplierName']
            buylinks[affiliate['supplierName'].to_s] = affiliate['buyLink']
        end
    end
    return buylinks['iTunes'] || buylinks['Amazon MP3']
  end
end

DataMapper.finalize.auto_upgrade!
scavenge_tracks

get '/' do
  @title = "All tracks"
  @tracks = Track.all( :date_uploaded.gt => (Time.now - (60 * 60 * 24 * 30)), :order => [ :date_uploaded.desc ] )
  erb :index
end

get '/new' do
  @title = "Upload form"
  erb :upload_form
end

post '/new' do
  # Check if the upload is too large (>15 MiB) and return a 413 Request too large
  if request.env['CONTENT_LENGTH'].to_i > 20728640
    status 413
    return "That upload is too large. Try to keep it under 15 megabytes."
  end

  # Handle the uploaded file and make sure it's the right type. TagLib can handle
  # MP3 and MPEG-4 audio files
  upload = params[:file]
  return %[No file uploaded. <a href="/new">Try again?</a>] if not upload
  unless ['audio/x-m4a', 'audio/mpeg', 'audio/mp3'].include? upload[:type]
    status 400
    return %[That wasn't an MP3 file. <a href="/new">Try again?</a>]
  end
  track_tempfile = {}
  track_tempfile[:id] = Time.now.strftime("%Y%m%d%H%M%S_#{Random.new.rand(10..99)}")
  track_tempfile[:ext] = File.extname(upload[:filename].gsub(/[^0-9A-Za-z\.]/i, ''))
  track_tempfile[:name] = "#{track_tempfile[:id]}-temp#{track_tempfile[:ext]}"
  File.open("files/#{track_tempfile[:name]}", 'w') do |f|
    f.write upload[:tempfile].read
  end

  # Lookup the tags, pull artwork from Last.fm, and save the resource
  TagLib::FileRef.open("files/#{track_tempfile[:name]}") do |fileref|
    if fileref.null? || [:title, :artist, :album].any? {|tag| fileref.tag.send(tag).to_s.empty? }
      status 400
      return "Could not process the ID3 tags on that track."
    end

    tags = fileref.tag
    @track = Track.new
    @track.title = tags.title.to_s[(0..1023)]
    @track.artist = tags.artist.to_s[(0..1023)]
    @track.album = tags.album.to_s[(0..1023)]
    @track.artwork = lastfm_get_artwork tags.artist.to_s, tags.album.to_s
    @track.path = "files/#{track_tempfile[:id]}_#{tags.title.to_s.gsub(/[^0-9A-Za-z\._-]/, '_')[0..50]}#{track_tempfile[:ext]}"
    @track.date_uploaded = Time.now
    @track.delete_key = generate_delete_key
    flash[:deletekey] = @track.delete_key
    @track.buylink = lastfm_get_buylink @track.artist, @track.title
    @track.plays = 0
    if not @track.save
      puts "---------- error saving #{@track.title} ------------ "
      @track.errors.each do |err|
        puts err.to_s
      end
      status 500
      return 'Unable to save new track.'
    end
    FileUtils.mv "files/#{track_tempfile[:name]}", @track.path

    redirect "/#{@track.id}/#{@track.title.to_s.gsub(/[^0-9A-Za-z\._-]/, '-')}-#{@track.artist.to_s.gsub(/[^0-9A-Za-z\._-]/, '-')}"
  end
end

get '/:id/?:slug?' do
  pass if params[:slug] =~ /.+\.(mp3|m4a)/
  @track = Track.get params[:id].to_i
  if !@track || @track.deleted
    status 404
    return "Could not find a track with that ID. It may have been deleted."
  end
  @title = "#{@track.title} by #{@track.artist}"
  unless session[:last_played] == @track.id
    session[:last_played] = @track.id
    @track.plays += 1
    @track.save!
  end
  erb :track
end

delete '/:id' do
  @track = Track.get params[:id].to_i
  if !@track || @track.deleted
    status 404
    return <<-END
      <html><head><title>Missing track</title></head><body>
      <p>Could not find a track with that ID. It may have been deleted.</p>
      <p><a href="/">Click here</a> to return.</p>
      </body></html>
    END
  end
  if not [APP_SETTINGS['master_delete_key'], @track.delete_key].include? params[:key]
    flash[:error] = "The provided delete key was incorrect."
    redirect "/#{params[:id]}"
  end
  begin
    FileUtils.rm(File.join('files', File.basename(@track.path)))
  rescue Errno::ENOENT
    flash[:d_info] = "Track file did not exist."
  end
  @track.deleted = true
  if @track.save
    flash[:info] = "Successfully deleted #{@track.title} by #{@track.artist}." + (flash[:d_info] || "")
    redirect "/"
  else
    status 500
    "There was a problem deleting that track."
  end
end

get '/files/:file' do
  file = File.join('files', params[:file])
  if not file
    status 404
    return "Could not find a track by that name."
  end
  send_file(file, :disposition => 'attachment', :filename => File.basename(file))
end


## Housekeeping
scheduler = Rufus::Scheduler.start_new
scheduler.every '1d' do
  scavenge_tracks
end
