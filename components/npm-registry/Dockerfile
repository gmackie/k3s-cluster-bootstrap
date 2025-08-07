FROM verdaccio/verdaccio:5

USER root

# Install the auth-proxy plugin for header-based authentication
RUN npm install --global verdaccio-auth-proxy

USER $VERDACCIO_USER_UID