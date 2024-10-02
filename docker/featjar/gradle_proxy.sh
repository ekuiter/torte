#!/bin/bash
# This script convinces Gradle to use the external proxy configuration passed from Docker via the environment.
mkdir -p $HOME/.gradle

PROXY=$(echo "$http_proxy" | sed 's#:/##g' | sed 's#/##g' | sed 's#[^0-9.:]##g')
HOST=$(echo "$PROXY" | cut -d: -f1)
PORT=$(echo "$PROXY" | cut -d: -f2)
echo systemProp.http.proxyHost=$HOST >> $HOME/.gradle/gradle.properties
echo systemProp.http.proxyPort=$PORT >> $HOME/.gradle/gradle.properties

PROXY=$(echo "$https_proxy" | sed 's#:/##g' | sed 's#/##g' | sed 's#[^0-9.:]##g')
HOST=$(echo "$PROXY" | cut -d: -f1)
PORT=$(echo "$PROXY" | cut -d: -f2)
echo systemProp.https.proxyHost=$HOST >> $HOME/.gradle/gradle.properties
echo systemProp.https.proxyPort=$PORT >> $HOME/.gradle/gradle.properties