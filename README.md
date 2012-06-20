### Octavia ###
A quick and dirty Sinatra app to take MP3 uploads, pull album art from Last.fm's API based on the the ID3 tags, and link to a page with the album art so that it shows up as a preview image on Facebook.

Named after [Octavia](http://mlp.wikia.com/wiki/Octavia) 'cause she's kind of a badass.

#### Installing ####
Need:
* Sinatra
* taglib
* libmagic (or a newish version of file)
* DataMapper
* sqlite3
* ruby-lastfm
* xmlsimple

Get an API key from Last.fm and put it into app.yml in the root of the application.
(example)
```
    lastfm:
            key:    '<api key>'
            secret: '<api secret>'
```
And run it. Use Daemons if you want to daemonize it.
