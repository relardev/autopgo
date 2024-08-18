# Use the official AlmaLinux image as a base
FROM almalinux:9

# Set environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ELIXIR_VERSION=1.17.2 \
    ERLANG_VERSION=26.2.5

RUN dnf -y install epel-release

# Install required dependencies
RUN dnf -y update && \
    dnf -y install \
    wget \
    git \
    tar \
    gcc \
    glibc-devel \
    make \
    ncurses-devel \
    openssl-devel \
    autoconf \
    m4 \
    unixODBC \
    libxslt \
    unzip \
    && dnf clean all

# Install Erlang
RUN curl -fsSL https://github.com/erlang/otp/releases/download/OTP-${ERLANG_VERSION}/otp_src_${ERLANG_VERSION}.tar.gz -o otp_src_${ERLANG_VERSION}.tar.gz \
    && tar -xzf otp_src_${ERLANG_VERSION}.tar.gz \
    && cd otp_src_${ERLANG_VERSION} \
    && ./configure \
    && make -j$(nproc) \
    && make install \
    && cd .. \
    && rm -rf otp_src_${ERLANG_VERSION} otp_src_${ERLANG_VERSION}.tar.gz

# Install Elixir
RUN curl -fsSL https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-26.zip -o elixir.zip \
    && unzip elixir.zip -d /usr/local/elixir \
    && rm elixir.zip \
    && ln -s /usr/local/elixir/bin/elixir /usr/local/bin/elixir \
    && ln -s /usr/local/elixir/bin/elixirc /usr/local/bin/elixirc \
    && ln -s /usr/local/elixir/bin/mix /usr/local/bin/mix \
    && ln -s /usr/local/elixir/bin/iex /usr/local/bin/iex

ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Set the working directory
WORKDIR /autopgo

# Copy the mix.exs and mix.lock files to the container
COPY mix.exs mix.lock ./

# Fetch and compile dependencies
RUN mix deps.get && mix deps.compile

# Copy the application code
COPY . .

# Build the release

RUN mix release
