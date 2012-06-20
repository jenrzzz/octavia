### Octavia ###
A quick and dirty Sinatra app to take MP3 uploads, pull album art from Last.fm's API based on the the ID3 tags, and link to a page with the album art so that it shows up as a preview image on Facebook.

Named after [Octavia](http://mlp.wikia.com/wiki/Octavia) 'cause she's kind of a badass.

#### Installing ####
Need:
* [Sinatra](http://www.sinatrarb.com/)
* [taglib](http://developer.kde.org/~wheeler/taglib.html)
* [ruby-taglib](http://www.hakubi.us/ruby-taglib/)
   Note that you need to change line 40 of ```taglib.rb``` from ```DL::Importable``` to ```DL::Importer``` for 1.9
* dl
* libmagic (or a newish version of [file](ftp://ftp.astron.com/pub/file/))
* DataMapper
* sqlite3
* [ruby-lastfm](https://github.com/youpy/ruby-lastfm)
* xmlsimple

Get an API key from Last.fm and put it into ```app.yml``` in the root of the application.
(example)
```
    lastfm:
            key:    '<api key>'
            secret: '<api secret>'
```
And run it. Use Daemons if you want to daemonize it.
