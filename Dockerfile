FROM ruby:2.3.3

EXPOSE 8080

WORKDIR /app
ADD . /app
RUN bundle install

CMD ["bundle","exec","rackup"]
