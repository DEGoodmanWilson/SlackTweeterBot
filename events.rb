require 'sinatra/base'
require 'slack-ruby-client'
require 'mongo'
require 'nokogiri'
require 'uri'
require 'json'
require_relative 'helpers'

# Fly me to the moon, let me dance among the stars...
class Events < Sinatra::Base

  # This function contains code common to all endpoints: JSON extraction, setting up some instance variables, and checking verification tokens (for security)
  before do
    body = request.body.read

    # Extract the Event payload from the request and parse the JSON. We can reasonably assume this will be present
    error = false
    begin
      @request_data = JSON.parse(body)
    rescue JSON::ParserError
      begin
        @request_data = JSON.parse(URI.decode body.split('=')[-1])
      rescue JSON::ParserError
        error = true
      end
    end

    if error
      # the payload might be URI encoded. Partly. Seriously. We'll need to try again. This happens for message actions webhooks only
      begin
        body = body.split('payload=', 2)[1]
        @request_data = JSON.parse(URI.decode(body))
      rescue JSON::ParserError => e
        halt 419, "Malformed event payload"
      end
    end

    # Check the verification token provided with the request to make sure it matches the verification token in
    # your app's setting to confirm that the request came from Slack.
    unless SLACK_CONFIG[:slack_verification_token] == @request_data['token']
      halt 403, "Invalid Slack verification token received: #{@request_data['token']}"
    end

    # What team generated this event?
    @team_id = @request_data['team_id']
    # maybe this is a message action, in which case we have to dig deeper. This is one place where the Slack API is maddeningly inconsistent
    @team_id = @request_data['team']['id'] if @team_id.nil? && @request_data['team']

    # Load up the Slack application tokens for this team and put them where we can reach them.
    @token = $tokens.find({team_id: @team_id}).first

    @client = create_slack_client(@token['bot_access_token'])

  end

  # This cool function allows us to write Sinatra endpoints for individual events of interest directly! How fun! Magic!
  set(:event) do |value|
    condition do
      # Each Slack event has a unique `type`. The `message` event also has a `subtype`, sometimes, that we can capture too.
      # Let's make message subtypes look like `message.subtype` for convenience
      return true if @request_data['type'] == value

      if @request_data['type'] == 'event_callback'
        type = @request_data['event']['type']
        unless @request_data['event']['subtype'].nil?
          type = type + '.' + @request_data['event']['subtype']
        end
        return true if type == value
      end

      return false
    end
  end

  ####################################
  # helper functions
  #

  def verify_twitter! channel
    response ='Please configure a Twitter account with `@tweeterbot twitter` or `@tweeterbot buffer`'

    twitter_token = @token['twitter_tokens'] || nil
    buffer_token = @token['buffer_tokens'] || nil
    @twitter_token = @token['twitter_tokens'][channel] || nil
    @buffer_token = @token['buffer_tokens'][channel] || nil

    unless @twitter_token || @buffer_token
      @client.chat_postMessage channel: channel, text: response
      halt 200
    end
  end

  # This method takes a `message` event that should be indexed, extracts all the links in that message, opens each of those
  # links (asynchronously of course!), flattens the HTML into plaintext, and crafts a tweet out of the result.
  def tweet_format message

    # We begin the hunt for links. The good news is that Slack marks them out for us!
    # Links look like:
    # <http://google.com>
    # or
    # <http://google.com|Google!>
    # We want to ignore the label, and just get the URL
    links = []
    message['text'].scan(/<(https?:\/\/.+?)>/).each do |m|
      url = m[0].split('|')[0]
      links.append url #URI.encode url
    end

    links.each do |link|
      response = Faraday.get link
      # We are now in our own thread, operating asynchronously. We can take our time here.

      # First, we use Nokogiri to extract the page title.
      page = Nokogiri::HTML(response.body)
      page.css('script, link, style').each {|node| node.remove}
      title = page.css('title').text

      # Now craft a tweet message; remember max is 140 chars!

      # First, check the current max length of a t.co link wrapper
      # TODO
      t_co = 20
      length = title.length + t_co + 1 # 1 for the space.
      delta = length - 140
      if delta > 0
        title = title[0..-delta-2] + '…'
      end

      return title + ' ' + link

    end
  end


  ####################################
  # Event handlers
  #

  # See? I said it would be fun. Here is the endpoint for handling the necessary events endpoint url verification, which
  # is a one-time step in the application creation process. We have to do it :( Exactly once. But it's easy.
  post '/events', :event => 'url_verification' do
    halt 200, @request_data['challenge']
  end


  # Now things get a bit more exciting. Here is the endpoint for handling user messages! We need to determine whether to
  # index, run a query, or ignore the message, and then possibly render a response.
  post '/events', :event => 'message' do

    message = @request_data['event']

    # First of all, ignore all message originating from us
    halt 200 if message['user'] == @token['bot_user_id']


    # at this point, lots of things could happen.
    # This could be an ambient message that we should scan for links to tweet
    # Or this could be a message directed at _us_, in which case we should treat it as a command.

    # The rule we're going to use is this:
    # Tweet only messages a) not addressed to us and b) in a public channel

    # Now, is this message addressed to us?
    is_addressed_to_us = !Regexp.new('<@'+@token['bot_user_id']+'>').match(message['text']).nil?

    # Is it in a DM?
    is_in_dm = message['channel'][0] == 'D'

    # Is it in a public channel?
    is_in_public_channel = message['channel'][0] == 'C'

    # Does the message satisfy the rule above? Index it!
    if is_in_public_channel && !is_addressed_to_us
      verify_twitter! message['channel']
      tweet = tweet_format message

      attachments = [{
                         text: 'Tweet this?',
                         callback_id: 'tweeter_tweet',
                         actions: [
                             {
                                 name: 'ignore',
                                 text: 'Ignore',
                                 type: 'button',
                                 value: 'Ignore'
                             }
                         ]}]

      twitter_button = { name: 'tweet', text: 'Tweet', type: 'button', value: 'Tweet' }
      attachments[0][:actions].append twitter_button if @twitter_token

      twitter_button = { name: 'buffer', text: 'Buffer', type: 'button', value: 'Buffer' }
      attachments[0][:actions].append twitter_button if @buffer_token

      @client.chat_postMessage channel: message['channel'], text: '> ' + tweet,
                               attachments: attachments
      status 200
      halt ""
    end

    # The other rule is: If the message is meant for us, then run a command. A message meant for us is a message
    # that @-mentions us, or else arrives in a DM with us.
    if is_in_dm || is_addressed_to_us

      # Format: @tweeterbot command params

      # Supported commands: config[ure]

      match = Regexp.new('(<@'+@token['bot_user_id']+'>:?)?(.*)').match message['text']
      commands = match[2].strip.split(' ')

      case commands[0]
        when 'twitter'
          link = 'https://' + ENV['HOST'] + '/install_twitter/' + @team_id +'/' + message['channel']
          @client.chat_postMessage channel: message['channel'], text: 'Please click here to authorize Twitter! ' + link
        when 'buffer'
          link = 'https://' + ENV['HOST'] + '/install_buffer/' + @team_id +'/' + message['channel']
          @client.chat_postMessage channel: message['channel'], text: 'Please click here to authorize Twitter! ' + link
        else
          @client.chat_postMessage channel: message['channel'], text: 'howdy!'
      end

      halt 200
    end

    # else, do nothing. Ignore the message.
    status 200
  end


  # Here is the endpoint for handling message actions
  # We end up here if someone clicked a button in one of our messages.
  post '/buttons' do

    # # So, someone hit "prev" or "next". Our job is to figure out
    # # a) what they were looking at and
    # # b) where they want to go
    # # c) and then reconstruct the message with the new data
    #
    # query_str = @request_data['callback_id'] # we stored the query in the callback id, so clever!
    # new_page = @request_data['actions'][0]['value'].to_i # and the new page to fetch here.
    #
    # #we have enough to run the query!
    # response = query query_str, new_page
    #
    # # Rather than posting a new message, we'll just respond with the new message to replace the old message! It's like a carousel
    # content_type :json
    # response.to_json
    status 200
  end
end