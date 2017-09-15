require 'sinatra/base'
require 'mongo'
require 'erb'
require 'oauth2'
require_relative 'helpers'

$temp_table = $db_client[:temp]

def get_client
  OAuth2::Client.new(ENV['BUFFER_CLIENT_ID'], ENV['BUFFER_CLIENT_ID'], site: 'https://bufferapp.com',
                     authorize_url: '/oauth2/authorize',
                     token_url: 'https://api.bufferapp.com/1/oauth2/token.json'
  )
end

# Buffer uses OAuth2 for user authentication.
class BufferAuth < Sinatra::Base
  # I want to use sessions, but I can't. Use mongo instead.

  get '/install_buffer/:team_id/:channel_id' do

    # TODO validate that these are team_ids and channel_ids we've seen before!

    team_id = params[:team_id]
    channel_id = params[:channel_id]
    client = get_client

    redirect client.auth_code.authorize_url(redirect_uri: 'https://' + ENV['HOST'] + '/install_buffer/finish/'+team_id+'/'+channel_id)
  end

  get '/install_buffer/finish/:team_id/:channel_id' do
    team_id = params[:team_id]
    channel_id = params[:channel_id]
    client = get_client

    access_token = client.auth_code.get_token(params[:code],
                                              client_id: ENV['BUFFER_CLIENT_ID'],
                                              client_secret: ENV['BUFFER_CLIENT_SECRET'],
                                              redirect_uri: 'https://' + ENV['HOST'] + '/install_buffer/finish/'+team_id+'/'+channel_id
    )

    # Store the token that we need to make API calls
    doc = $tokens.find({team_id: params[:team_id]}).first
    doc['buffer_tokens'][params[:channel_id]] = {oauth_token: access_token.token}
    $tokens.update_one({team_id: params[:team_id]}, doc)

    status 200
    body "Buffer configured!"
  end

end
