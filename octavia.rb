require 'sinatra'
require 'data_mapper'
require 'taglib'
require 'lastfm'
require 'yaml'
require 'xmlsimple'

DataMapper::Logger.new(STDOUT, :debug)
DataMapper.setup :default, "sqlite3://#{Dir.pwd}/data.db"

if not Dir.exists? 'files'
  Dir.mkdir 'files'
end

APP_SETTINGS = YAML.load(File.open(File.join(File.dirname(__FILE__), 'app.yml')))

$LAST_FM = Lastfm.new(APP_SETTINGS['lastfm']['key'], APP_SETTINGS['lastfm']['secret'])
$LAST_FM_TOKEN = $LAST_FM.auth.get_token

configure do
  enable :static, :logging
end

class Track
  include DataMapper::Resource
  property :id,       Serial
  property :title,    String, :length => 255
  property :artist,   String, :length => 255
  property :album,    String, :length => 255
  property :artwork,  String, :length => 255
  property :path,     String, :length => 255
end

DataMapper.finalize.auto_upgrade!

helpers do
  def lastfm_get_artwork(artist, album)
    info = $LAST_FM.album.get_info artist, album
    info['image'].each do |item|
      if item['size'] == 'extralarge'
        return item['content'].strip
      end
    end
  end
end

get '/' do
  @title = "All tracks"
  @tracks = Track.all :order => [ :artist.asc ]
  erb :index
end

get '/new' do
  @title = "Upload form"
  erb :upload_form
end

post '/new' do
  upload = params[:file]
  filename = Time.now.strftime('%Y%m%d%H%M%S-') + (upload[:filename].gsub(/ /, '_').downcase)
  unless ['audio/mpeg', 'audio/mp3'].include? upload[:type]
    puts "Upload type is #{upload[:type]} instead of audio/mpeg"
    status 400
    return %[That wasn't an MP3 file. <a href="/new">Try again?</a>]
  end
  File.open("files/#{filename}", 'w') do |f|
    f.write upload[:tempfile].read
  end
  tags = TagLib::File.new("files/#{filename}")
  @track = Track.new
  @track.title = tags.title
  @track.artist = tags.artist
  @track.album = tags.album
  @track.artwork = lastfm_get_artwork tags.artist, tags.title
  @track.path = "files/#{filename}"
  if not @track.save
    puts "---------- error saving #{@track.title} ------------ "
    @track.errors.each do |e|
      puts e.to_s
    end
    status 500
    'Unable to save new track.'
  else
    redirect "/#{@track.id}"
  end
end

get '/:id' do
  @track = Track.get params[:id].to_i
  @title = "#{@track.title} by #{@track.artist}"
  if not @track
    status 404
    "Could not find a track with that ID."
  end
  erb :track
end

get '/files/:file' do
  file = File.join('files', params[:file])
  if not file
    status 404
    "Could not find a track by that name."
  end
  send_file(file, :disposition => 'attachment', :filename => File.basename(file))
end
