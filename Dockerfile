# Rails 8 用。NodeやJSビルド不要の最小構成
FROM ruby:3.3.4

ENV BUNDLER_VERSION=2.5.10
RUN apt-get update -y && apt-get install -y --no-install-recommends \
  build-essential libpq-dev curl git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v ${BUNDLER_VERSION} && bundle install

COPY . .

# 初回はコンテナ内で rails new 実行 → 以降は通常起動
CMD ["bash", "-lc", "bin/rails s -b 0.0.0.0"]
