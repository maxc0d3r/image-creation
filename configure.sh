#!/bin/bash
#Script to setup some environment variables

export JAVA_HOME=/usr/local/java/default
export EC2_CERT=/opt/ec2/keys/cert.pem
export EC2_PRIVATE_KEY=/opt/ec2/keys/pk.pem
export EC2_HOME=/opt/ec2/api-tools
export EC2_AMITOOL_HOME=/opt/ec2/ami-tools
export EC2_APITOOL_HOME=$EC2_HOME
export PATH=$PATH:$EC2_AMITOOL_HOME/bin:$EC2_APITOOL_HOME/bin
export ACCESS_KEY=
export SECRET_ACCESS_KEY=
