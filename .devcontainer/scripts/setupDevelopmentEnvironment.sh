#!/bin/bash
set -Eeuo pipefail
# shellcheck disable=SC2064
trap "pkill -P $$" EXIT

# Database Information
POSTGRES_CONNECTION_STRING="postgres://postgres:supersecret@localhost:5432/ccdb"
MYSQL_CONNECTION_STRING="mysql2://root:supersecret@127.0.0.1:3306/ccdb"

setupPostgres () {
    export DB="postgres"
    export DB_CONNECTION_STRING="${POSTGRES_CONNECTION_STRING}"
    bundle exec rake db:recreate
    bundle exec rake db:migrate
    bundle exec rake db:seed
}

setupMariadb () {
    export DB="mysql"
    export DB_CONNECTION_STRING="${MYSQL_CONNECTION_STRING}"
    bundle exec rake db:recreate
    bundle exec rake db:migrate
    bundle exec rake db:seed
}

setupUAA () {
    # Wait until ready
    # shellcheck disable=SC2016
    timeout 300 bash -c 'while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://localhost:8080/info)" != "200" ]]; do sleep 5; done' || false

    # Login
    uaac target http://localhost:8080 --skip-ssl-validation
    uaac token client get admin -s "adminsecret"

    # Admin User
    NEW_ADMIN_USERNAME="ccadmin"
    NEW_ADMIN_PASSWORD="secret"
    uaac user add ${NEW_ADMIN_USERNAME} -p ${NEW_ADMIN_PASSWORD} --emails fake@example.com
    uaac member add cloud_controller.admin ${NEW_ADMIN_USERNAME}
    uaac member add uaa.admin ${NEW_ADMIN_USERNAME}
    uaac member add scim.read ${NEW_ADMIN_USERNAME}
    uaac member add scim.write ${NEW_ADMIN_USERNAME}

    # Dasboard User
    uaac user add cc-service-dashboards -p some-sekret --emails fake2@example.com
}

# CC config
mkdir -p tmp
cp -a config/cloud_controller.yml tmp/cloud_controller.yml

yq -i e '.login.url="http://localhost:8080"' tmp/cloud_controller.yml
yq -i e '.login.enabled=true' tmp/cloud_controller.yml

yq -i e '.nginx.use_nginx=true' tmp/cloud_controller.yml
yq -i e '.nginx.instance_socket=""' tmp/cloud_controller.yml

yq -i e '.logging.file="tmp/cloud_controller.log"' tmp/cloud_controller.yml
yq -i e '.telemetry_log_path="tmp/cloud_controller_telemetry.log"' tmp/cloud_controller.yml
yq -i e '.directories.tmpdir="tmp"' tmp/cloud_controller.yml
yq -i e '.directories.diagnostics="tmp"' tmp/cloud_controller.yml
yq -i e '.security_event_logging.enabled=true' tmp/cloud_controller.yml
yq -i e '.security_event_logging.file="tmp/cef.log"' tmp/cloud_controller.yml

yq -i e '.uaa.url="http://localhost:8080"' tmp/cloud_controller.yml
yq -i e '.uaa.internal_url="http://localhost:8080"' tmp/cloud_controller.yml
yq -i e '.uaa.resource_id="cloud_controller"' tmp/cloud_controller.yml
yq -i e 'del(.uaa.symmetric_secret)' tmp/cloud_controller.yml

yq -i e '.resource_pool.fog_connection.provider="AWS"' tmp/cloud_controller.yml
yq -i e '.resource_pool.fog_connection.endpoint="http://localhost:9001"' tmp/cloud_controller.yml
yq -i e '.resource_pool.fog_connection.aws_access_key_id="minioadmin"' tmp/cloud_controller.yml
yq -i e '.resource_pool.fog_connection.aws_secret_access_key="minioadmin"' tmp/cloud_controller.yml
yq -i e '.resource_pool.fog_connection.aws_signature_version=2' tmp/cloud_controller.yml
yq -i e '.resource_pool.fog_connection.path_style=true' tmp/cloud_controller.yml

yq -i e '.packages.fog_connection.provider="AWS"' tmp/cloud_controller.yml
yq -i e '.packages.fog_connection.endpoint="http://localhost:9001"' tmp/cloud_controller.yml
yq -i e '.packages.fog_connection.aws_access_key_id="minioadmin"' tmp/cloud_controller.yml
yq -i e '.packages.fog_connection.aws_secret_access_key="minioadmin"' tmp/cloud_controller.yml
yq -i e '.packages.fog_connection.aws_signature_version=2' tmp/cloud_controller.yml
yq -i e '.packages.fog_connection.path_style=true' tmp/cloud_controller.yml

yq -i e '.droplets.fog_connection.provider="AWS"' tmp/cloud_controller.yml
yq -i e '.droplets.fog_connection.endpoint="http://localhost:9001"' tmp/cloud_controller.yml
yq -i e '.droplets.fog_connection.aws_access_key_id="minioadmin"' tmp/cloud_controller.yml
yq -i e '.droplets.fog_connection.aws_secret_access_key="minioadmin"' tmp/cloud_controller.yml
yq -i e '.droplets.fog_connection.aws_signature_version=2' tmp/cloud_controller.yml
yq -i e '.droplets.fog_connection.path_style=true' tmp/cloud_controller.yml

yq -i e '.buildpacks.fog_connection.provider="AWS"' tmp/cloud_controller.yml
yq -i e '.buildpacks.fog_connection.endpoint="http://localhost:9001"' tmp/cloud_controller.yml
yq -i e '.buildpacks.fog_connection.aws_access_key_id="minioadmin"' tmp/cloud_controller.yml
yq -i e '.buildpacks.fog_connection.aws_secret_access_key="minioadmin"' tmp/cloud_controller.yml
yq -i e '.buildpacks.fog_connection.aws_signature_version=2' tmp/cloud_controller.yml
yq -i e '.buildpacks.fog_connection.path_style=true' tmp/cloud_controller.yml

yq -i e '.cloud_controller_username_lookup_client_name="login"' tmp/cloud_controller.yml
yq -i e '.cloud_controller_username_lookup_client_secret="loginsecret"' tmp/cloud_controller.yml

# Install packages
bundle config set --local with 'debug'
bundle install

# Setup Containers
setupPostgres || tee tmp/fail &
setupMariadb || tee tmp/fail &
setupUAA || tee tmp/fail &

# Wait for background jobs and exit 1 if any error happened
# shellcheck disable=SC2046
wait $(jobs -p)
test -f tmp/fail && rm tmp/fail && exit 1

trap "" EXIT