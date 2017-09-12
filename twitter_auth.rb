require 'sinatra/base'
require 'twitter'
require 'mongo'
require 'erb'
require 'twitter'
require 'oauth'
require_relative 'helpers'

$temp_table = $db_client[:temp]

# # Load Twitter app info into a hash called `config` from the environment variables assigned during setup
# # See the "Running the app" section of the README for instructions.
# TWITTER_CONFIG = {
#     consumer_key: ENV['TWITTER_CONSUMER_KEY'],
#     consumer_secret: ENV['TWITTER_CONSUMER_SECRET']
# }
#
# # Check to see if the required variables listed above were provided, and raise an exception if any are missing.
# missing_params = TWITTER_CONFIG.select {|key, value| value.nil?}
# if missing_params.any?
#   error_msg = missing_params.keys.join(", ").upcase
#   raise "Missing Twitter config variables: #{error_msg}"
# end
#

def get_consumer
  OAuth::Consumer.new(
      ENV['TWITTER_CONSUMER_KEY'],
      ENV['TWITTER_CONSUMER_SECRET'],
      {:site => 'https://api.twitter.com/'}
  )
end

# Twitter uses OAuth for user authentication. This auth process is performed by exchanging a set of
# keys and tokens between Twitter's servers and yours. This process allows the authorizing user to confirm
# that they want to grant our bot access to their team.
# See https://api.twitter.com/docs/oauth for more information.
class TwitterAuth < Sinatra::Base
  # I want to use sessions, but I can't. Use mongo instead.

  get '/install_twitter/:team_id/:channel_id' do

    # TODO validate that these are team_ids and channel_ids we've seen before!

    team_id = params[:team_id]
    channel_id = params[:channel_id]
    consumer = get_consumer
    request_token = consumer.get_request_token oauth_callback: ('https://' + ENV['HOST'] + '/install_twitter/finish/'+team_id+'/'+channel_id)

# Store the request token's details for later
    $temp_table.update_one({team_id: team_id, channel_id: channel_id},
                           {team_id: team_id, channel_id: channel_id, request_token: request_token.token, request_secret: request_token.secret},
                           {upsert: true})

# Hand off to Twitter so the user can authorize us
    redirect request_token.authorize_url
  end

  get '/install_twitter/finish/:team_id/:channel_id' do
    consumer = get_consumer

    request_token = $temp_table.find({team_id: params[:team_id], channel_id: params[:channel_id]}).first

    puts request_token[:request_token]

    # Re-create the request token
    request_token = OAuth::RequestToken.new(consumer,
                                            request_token[:request_token], request_token[:request_secret])

    # Convert the request token to an access token using the verifier Twitter gave us
    access_token = request_token.get_access_token oauth_verifier: params[:oauth_verifier]

    # Store the token and secret that we need to make API calls

    doc = $tokens.find({team_id: params[:team_id]}).first
    doc['twitter_tokens'][params[:channel_id]] = {oauth_token: access_token.token, oauth_secret: access_token.secret}
    $tokens.update_one({team_id: params[:team_id]}, doc)

    status 200
    body "Twitter configured!"
  end

end
