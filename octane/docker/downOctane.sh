#!/bin/bash

docker stop octane octane_es octane_oracle
docker rm -v octane octane_es octane_oracle
docker network rm octane_nw

sudo rm -rf /usr/lib/oracle/xe /var/elasticsearch/data /opt/octane
