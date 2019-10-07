#!/bin/bash
# Install a GCIS Data Gateway on a Linux server
# Prerequisites:
# - The docker engine and docker-compose have been installed
# - A sudoer user has been set up to perform the installation
# - The user gatewayuser has been created
# - The user gatewayuser has logged in to the docker hub with a correct credentials
#
# For example, the following commands will set up the prerequisites and install a Data Gateway on an Amazon Linux 2 system
# sudo yum install docker -y
# sudo systemctl enable docker
# sudo systemctl start docker
# sudo curl -L https://github.com/docker/compose/releases/download/1.24.1/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
# sudo chmod +x /usr/local/bin/docker-compose
# sudo adduser gatewayuser --system -g docker
# sudo su - gatewayuser -c "docker login"
# sudo ./setup-gateway https://api-uk.integration.gentrack.cloud gw-energise.integration.gentrack.cloud ./docker-compose.yml
#
#PLATFORM_URL=https://api-uk.integration.gentrack.cloud
#GATEWAY_DNS=gateway-uk.integration.gentrack.cloud
die() {
	echo >&2 "$@"
	exit 1
}
[ "$#" -eq 3 ] || die "Usage: $0 [GCIS API Url] [Gateway DNS name or IP address] [Docker Compose File]"
PLATFORM_URL=$1
GATEWAY_DNS=$2
DOCKER_COMPOSE_SRC=$3
[ -f "$DOCKER_COMPOSE_SRC" ] || die "File $DOCKER_COMPOSE_SRC does not exist"

GATEWAY_USER=gatewayuser
GATEWAY_USER_HOME=/home/$GATEWAY_USER
INSTALL_DIR=$GATEWAY_USER_HOME/platform
DOCKER_COMPOSE=$INSTALL_DIR/docker-compose.yml

RABBITMQ_DEFAULT_USER=rabbitmq
# Generate a 32-character long random password for RabbitMQ
RABBITMQ_DEFAULT_PASS=$(tr </dev/urandom -dc _A-Z-a-z-0-9 | head -c32)
if [ "${#RABBITMQ_DEFAULT_PASS}" -ne "32" ]; then
	die "Failed to generate password for RabbitMQ"
fi
MESSAGE_QUEUE_URL=$RABBITMQ_DEFAULT_USER:$RABBITMQ_DEFAULT_PASS@mq
# Check to make sure the compose file has expected format
grep -E "^(\s|\t)*RABBITMQ_DEFAULT_USER:.*$" $DOCKER_COMPOSE_SRC >/dev/null || die "Couldn't find RABBITMQ_DEFAULT_USER in $DOCKER_COMPOSE_SRC"
grep -E "^(\s|\t)*RABBITMQ_DEFAULT_PASS:.*$" $DOCKER_COMPOSE_SRC >/dev/null || die "Couldn't find RABBITMQ_DEFAULT_PASS in $DOCKER_COMPOSE_SRC"
grep -E "^(\s|\t)*- MESSAGE_QUEUE=.*$" $DOCKER_COMPOSE_SRC >/dev/null || die "Couldn't find MESSAGE_QUEUE in $DOCKER_COMPOSE_SRC"
(
	# stop and remove containers - ignore any erros
	usermod -a -G docker $(id -u -n) || die "Failed to add user to docker group"
	docker stop $(docker ps -aq) >/dev/null 2>&1
	docker rm $(docker ps -aq) >/dev/null 2>&1
	docker volume prune -f >/dev/null 2>&1
) || die "Failed to clean up dockers"

(
	rm -rf $INSTALL_DIR &&
		mkdir -p $INSTALL_DIR &&
		tr -d "\r" <$DOCKER_COMPOSE_SRC >$DOCKER_COMPOSE &&
		GATEWAY_APP_IMAGE=$(grep -E "^(\s|\t)*image: index.docker.io/gentrackio/gateway:PROD$" $DOCKER_COMPOSE)
	if [[ ! -z ${GATEWAY_APP_IMAGE} ]]; then
		if [ "$PLATFORM_URL" == "https://api-uk.integration.gentrack.cloud" ]; then
			GATEWAY_APP_IMAGE_UPDATED="${GATEWAY_APP_IMAGE}-UK"
		elif [ "$PLATFORM_URL" == "https://api-au.integration.gentrack.cloud" ]; then
			GATEWAY_APP_IMAGE_UPDATED="${GATEWAY_APP_IMAGE}-AU"
		fi
	fi
	([[ -z $GATEWAY_APP_IMAGE_UPDATED ]] || sed -i "s/${GATEWAY_APP_IMAGE//\//\\/}$/${GATEWAY_APP_IMAGE_UPDATED//\//\\/}/g" $DOCKER_COMPOSE) &&
		sed -i "s/- MESSAGE_QUEUE=.*\$/- MESSAGE_QUEUE=amqp:\/\/$MESSAGE_QUEUE_URL/g" $DOCKER_COMPOSE &&
		sed -i "s/RABBITMQ_DEFAULT_USER:.*\$/RABBITMQ_DEFAULT_USER: $RABBITMQ_DEFAULT_USER/g" $DOCKER_COMPOSE &&
		sed -i "s/RABBITMQ_DEFAULT_PASS:.*\$/RABBITMQ_DEFAULT_PASS: $RABBITMQ_DEFAULT_PASS/g" $DOCKER_COMPOSE &&
		chown $GATEWAY_USER $DOCKER_COMPOSE &&
		touch $INSTALL_DIR/http_check.yaml &&
		touch $INSTALL_DIR/key.txt &&
		# up and down to initalise named volumes
		su - $GATEWAY_USER -c "docker-compose -f $DOCKER_COMPOSE up -d" &&
		su - $GATEWAY_USER -c "docker-compose -f $DOCKER_COMPOSE down"
) || die "Failed to initalise volumes"

VAULT_CONFIG='{
  "backend": {"file": {"path": "/data/vault/file"}},
  "listener": {"tcp": {"address": "0.0.0.0:8200", "tls_cert_file": "/data/vault/cert/vault.crt", "tls_key_file": "/data/vault/cert/vault.key"}},
  "default_lease_ttl": "168h",
  "max_lease_ttl": "720h"
}'
CERT_SUBJ='/C=NZ/ST=Auckland/L=Auckland/O=Gentrack Ltd/OU=Platform/CN=gentrack.io/emailAddress=noreply@gentrack.io'
INSTALL_TMP=$(mktemp /tmp/platform.XXXXXXXXXX)
(
	rm $INSTALL_TMP &&
		mkdir -p $INSTALL_TMP/config &&
		tr </dev/urandom -dc 'A-Za-z0-9!"#$%&'\''()*+,-./:;<=>?@[\]^_`{|}~' | head -c 64 >$INSTALL_TMP/key.txt &&
		(
			echo platformUrl: $PLATFORM_URL
			echo hostname: $GATEWAY_DNS
		) >$INSTALL_TMP/default.yml &&
		echo $VAULT_CONFIG >$INSTALL_TMP/config/vault.json &&
		CERT_PATH="$INSTALL_TMP/vault/cert" &&
		mkdir -p $CERT_PATH &&
		$(openssl req -x509 -nodes -newkey rsa:4096 -keyout "$CERT_PATH/vault.key" -out "$CERT_PATH/vault.crt" -days 3650 -subj "$CERT_SUBJ")
) || die "Failed to create gateway configuration"
(
	GATEWAY_CONFIG_VOL=$(docker volume ls | grep GatewayConfig | rev | cut -d ' ' -f 1 | rev) &&
		GATEWAY_CONFIG_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' $GATEWAY_CONFIG_VOL) &&
		VAULT_DATA_VOL=$(docker volume ls | grep VaultData | rev | cut -d ' ' -f 1 | rev) &&
		VAULT_DATA_PATH=$(docker volume inspect --format '{{ .Mountpoint }}' $VAULT_DATA_VOL) &&
		cp $INSTALL_TMP/key.txt $INSTALL_DIR &&
		cp $INSTALL_TMP/default.yml $GATEWAY_CONFIG_PATH &&
		cp -r $INSTALL_TMP/config $VAULT_DATA_PATH/ &&
		cp -r $INSTALL_TMP/vault $VAULT_DATA_PATH/ && rm -rf $INSTALL_TMP
) || die "Failed to apply gateway configuration"

# daily job to automatically cleanup old Docker images and volumes
(
	GATEWAY_DOCKER_CLEANUP='/etc/cron.daily/docker-cleanup' &&
		echo "#!/bin/sh" | tee $GATEWAY_DOCKER_CLEANUP >/dev/null &&
		echo "docker rmi \$(docker images -qf dangling=true); true" | sudo tee -a $GATEWAY_DOCKER_CLEANUP >/dev/null &&
		chmod 700 $GATEWAY_DOCKER_CLEANUP && echo "Added daily job to automatically cleanup old Docker images"
) || die "Failed to add daily job to automatically cleanup old Docker images"

# daily job to delete old gateway logs
(
	GATEWAY_LOG_CLEANUP='/etc/cron.daily/gateway-log-cleanup' &&
		echo "#!/bin/sh" | tee $GATEWAY_LOG_CLEANUP >/dev/null &&
		echo "find /var/lib/docker/volumes/platform_GatewayData/_data/logs -name \"*.log\" -mtime +6 -exec rm {} \;" | sudo tee -a $GATEWAY_LOG_CLEANUP >/dev/null &&
		chmod 700 $GATEWAY_LOG_CLEANUP && echo "Added daily job to delete old gateway logs"
) || die "Failed to add daily job to delete old gateway logs"

# Generate http_check.yaml in platform directory for Datadog:
(
	HTTP_CHECK=$INSTALL_DIR/http_check.yaml &&
		cat >$HTTP_CHECK <<EOL
init_config:
instances:
 - name: Rackspace Data Gateway
   url: https://app:3000
   disable_ssl_validation: true
   check_certificate_expiration: true
   timeout: 1
EOL
) || die "Failed to generate http_check.yaml in platform directory for Datadog"

# Configure gentrack-gateway-docker.service:
(
	SYSTEMD_PATH='/etc/systemd/system'
	if [ ! -d $SYSTEMD_PATH ]; then
		echo "Unable to configure gentrack-gateway-docker.service becuase Systemd not exists, run docker-compose instead." &&
			su - $GATEWAY_USER -c "docker-compose -f $DOCKER_COMPOSE up -d" && echo "Success"

	else
		# docker.service override
		/bin/mkdir -p /etc/systemd/system/docker.service.d/
		DOCKER_SERVICE_OVERRIDE='/etc/systemd/system/docker.service.d/override.conf' &&
			cat >$DOCKER_SERVICE_OVERRIDE <<EOL
[Unit]
Before=gentrack-gateway-docker.service
Requires=gentrack-gateway-docker.service
EOL
		systemctl daemon-reload && echo "systemctl daemon reloaded" &&
			# gateway docker service
			GATEWAY_DOCKER_SERVICE='/etc/systemd/system/gentrack-gateway-docker.service' &&
			cat >$GATEWAY_DOCKER_SERVICE <<EOL
[Unit]
Description=Gentrack Data Gateway
After=docker.service proc-sys-fs-binfmt_misc.mount proc-sys-fs-binfmt_misc.automount
Requires=docker.service proc-sys-fs-binfmt_misc.mount proc-sys-fs-binfmt_misc.automount

[Service]
Type=simple
User=gatewayuser
Group=docker
Restart=always
ExecStart=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker-compose.yml up
ExecStop=/usr/local/bin/docker-compose -f $INSTALL_DIR/docker-compose.yml down

[Install]
WantedBy=multi-user.target
EOL
		systemctl enable gentrack-gateway-docker && echo "gentrack-gateway-docker.service enabled" &&
			systemctl start gentrack-gateway-docker && echo "gentrack-gateway-docker.service started"
	fi
) || die "Failed at configuring gentrack-gateway-docker.service"
