FROM ruby:2.3.3

EXPOSE 8080

RUN gem install sinatra slack-ruby-client mongo nokogiri buffer oauth2 faraday
WORKDIR /app
ADD . /app
RUN bundle install

CMD ["bundle","exec","rackup"]
