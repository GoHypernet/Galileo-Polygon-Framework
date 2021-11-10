# get the go runtime
FROM golang as go

# get the Galileo IDE
FROM hypernetlabs/galileo-ide:linux AS galileo-ide

# Final build stage
FROM rabbitmq:3.9-management

# enable noninteractive installation of deadsnakes/ppa
RUN apt update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata --fix-missing

# install geth, python, node, and smart contract development tooling
RUN apt update -y \
  && apt install -y software-properties-common gpg build-essential \
  && add-apt-repository -y ppa:deadsnakes/ppa \
  && apt update -y \
  && apt install -y \
    supervisor kmod fuse\
    python3.8 python3-pip python3.8-dev \
    libsecret-1-dev \
	vim curl tmux git zip unzip vim speedometer net-tools \
  && curl -fsSL https://deb.nodesource.com/setup_12.x | bash - \
  && apt install -y nodejs \
  && curl https://rclone.org/install.sh | bash \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash galileo

# get the go runtime
COPY --from=go --chown=galileo /go /go
COPY --from=go --chown=galileo /usr/local/go /usr/local/go
ENV PATH $PATH:/usr/local/go/bin:/home/galileo:/home/galileo/.local/bin
ENV GOPATH=/usr/local/go

RUN go get -u github.com/bitnami/bcrypt-cli

COPY --chown=galileo .theia /home/galileo/.theia
COPY --chown=galileo .vscode /home/galileo/.vscode

# get the Caddy server executables and stuff
COPY --from=galileo-ide --chown=galileo /caddy/caddy /usr/bin/caddy
COPY --from=galileo-ide --chown=galileo /caddy/header.html /etc/assets/header.html
COPY --from=galileo-ide --chown=galileo /caddy/users.json /etc/gatekeeper/users.json
COPY --from=galileo-ide --chown=galileo /caddy/auth.txt /etc/gatekeeper/auth.txt
COPY --from=galileo-ide --chown=galileo /caddy/settings.template /etc/gatekeeper/assets/settings.template
COPY --from=galileo-ide --chown=galileo /caddy/login.template /etc/gatekeeper/assets/login.template
COPY --from=galileo-ide --chown=galileo /caddy/custom.css /etc/assets/custom.css
COPY --chown=galileo rclone.conf /home/galileo/.config/rclone/rclone.conf
COPY --chown=galileo Caddyfile /etc/

# get the galileo IDE
COPY --from=galileo-ide --chown=galileo /.galileo-ide /home/galileo/.galileo-ide

RUN npm install -g mocha && npm i -g @project-serum/anchor-cli

WORKDIR /home/galileo
RUN git clone https://github.com/maticnetwork/heimdall \
  && git clone https://github.com/maticnetwork/bor \
  && git clone https://github.com/maticnetwork/launch

WORKDIR /home/galileo/heimdall
RUN git checkout v0.2.4 && make install 

WORKDIR /home/galileo/bor
RUN git checkout v0.2.4 && make bor-all \
  && ln -nfs ~/bor/build/bin/bor /usr/bin/bor \
  && ln -nfs ~/bor/build/bin/bootnode /usr/bin/bootnode

USER galileo
WORKDIR /home/galileo/.galileo-ide
ENV HOME=/home/galileo

# get supervisor configuration file
COPY supervisord.conf /etc/

# set environment variable to look for plugins in the correct directory
ENV SHELL=/bin/bash \
    THEIA_DEFAULT_PLUGINS=local-dir:/home/galileo/.galileo-ide/plugins
ENV USE_LOCAL_GIT true
ENV GALILEO_RESULTS_DIR /home/galileo

# set login credentials and write them to text file
ENV USERNAME "a"
ENV PASSWORD "a"
RUN sed -i 's,"username": "","username": "'"$USERNAME"'",1' /etc/gatekeeper/users.json && \
    sed -i 's,"hash": "","hash": "'"$(echo -n "$(echo $PASSWORD)" | bcrypt-cli -c 10 )"'",1' /etc/gatekeeper/users.json

ENTRYPOINT ["sh", "-c", "supervisord"]