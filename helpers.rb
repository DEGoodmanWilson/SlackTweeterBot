require 'slack-ruby-client'

# Since we're going to create a Slack client object for each team, this helper keeps all of that logic in one place.
def create_slack_client(slack_api_secret)
  Slack.configure do |config|
    config.token = slack_api_secret
    fail 'Missing API token' unless config.token
  end
  # Slack::Web::Client.new( endpoint: 'http://localhost:3000/api')
  Slack::Web::Client.new
end

def create_twitter_client(config)
  $twitter_client = Twitter::REST::Client.new do |config|
    config.consumer_key        = config['consumer_key']
    config.consumer_secret     = "YOUR_CONSUMER_SECRET"
    config.access_token        = "YOUR_ACCESS_TOKEN"
    config.access_token_secret = "YOUR_ACCESS_SECRET"
  end
end


# A method to truncate a string!
class String
  def truncate(max)
    length > max ? "#{self[0...max]}..." : self
  end
end