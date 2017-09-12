#\ -p 8080 -o 0

require './slack_auth'
require './twitter_auth'
require './events'

# Initialize the app and create the API (bot) and Auth objects.
run Rack::Cascade.new [SlackAuth, TwitterAuth, Events]
