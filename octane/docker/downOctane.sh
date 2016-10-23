#!/bin/bash

docker stop octane octane_es octane_ora
docker rm -v octane octane_es octane_ora
docker network rm octane_nw

sudo rm -rf /usr/lib/oracle/xe /var/elasticsearch/data /opt/octane
