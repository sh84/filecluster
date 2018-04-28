FROM ubuntu:16.04

RUN  apt-get update \
  && apt-get install -y wget \
  build-essential \
  zlib1g-dev \
  openssl \
  libssl-dev \
  git \
  libreadline-dev \
  libmysqlclient-dev \
  tzdata \
  super \
  && rm -rf /var/lib/apt/lists/*

RUN wget http://ftp.ruby-lang.org/pub/ruby/2.3/ruby-2.3.3.tar.gz \
  && tar -xzvf ruby-2.3.3.tar.gz \
  && rm ruby-2.3.3.tar.gz \
  && cd ruby-2.3.3/ \
  && ./configure --with-openssl-dir=/usr/bin \
  && make \
  && make install \
  && cd .. \
  && rm -rf ruby-2.3.3 \
  && gem install bundler

RUN mkdir -p /app
WORKDIR /app

COPY ./ /app

RUN groupadd --gid 1000 filecluster \
    && useradd --uid 1000 --gid 1000 filecluster --shell /bin/bash


COPY ./entrypoint.sh /usr/local/bin/
RUN bundle install --jobs 20 --retry 6

ENTRYPOINT  ["/usr/local/bin/entrypoint.sh"]
CMD ["/app/bin/fc-daemon", "-l", "debug"]
