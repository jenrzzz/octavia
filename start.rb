#!/usr/bin/env ruby
require 'daemons'
pwd = Dir.pwd
Daemons.run_proc('octavia.rb', { :dir_mode => :normal, :dir => "#{pwd}/pids" }) do
    Dir.chdir pwd
    exec "ruby octavia.rb -p 3001 -e production"
end
