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
COPY ./docker/keys/ /root/.ssh/
RUN chown root. -R /root/.ssh/ \
     &&  chmod 0600 /root/.ssh/id_rsa

COPY ./entrypoint.sh /usr/local/bin/
RUN bundle install --jobs 20 --retry 6

ENTRYPOINT  ["/usr/local/bin/entrypoint.sh"]
CMD ["/app/bin/fc-daemon", "-l", "debug"]
