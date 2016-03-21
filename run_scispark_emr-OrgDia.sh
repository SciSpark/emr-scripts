#!/bin/bash

# This script will run a toy Spark example on Amazon EMR as described here:
#   https://aws.amazon.com/blogs/aws/new-apache-spark-on-amazon-emr/
# The sample data sits on S3 in us-east-1 so run this script there.


# what to do if a step fails: TERMINATE_CLUSTER, CANCEL_AND_WAIT
STEP_FAILURE_ACTION=TERMINATE_CLUSTER

# uncomment to termination protection on
TERMINATION_PROTECTED=--termination-protected

# uncomment to auto terminate
#AUTO_TERMINATE=--auto-terminate

# subnet id
SUBNET_ID=subnet-6713b04d

# master & slave security group id
MASTER_SG_ID=sg-e571c99d
SLAVE_SG_ID=sg-6d73cb15

# S3 URI for logs
LOG_URI=s3n://aws-logs-052078438257-us-east-1/elasticmapreduce/


# create cluster
json=$(aws emr create-cluster $TERMINATION_PROTECTED $AUTO_TERMINATE \
  --applications Name=Hadoop Name=Hive Name=Spark Name=Zeppelin-Sandbox \
  --bootstrap-actions '[{"Path":"s3://scispark-bootstrap-scripts/emr-bootstrap-no-jplsec.sh",
                         "Name":"Custom action"}]' \
  --ec2-attributes "{\"KeyName\":\"scispark\",
                     \"InstanceProfile\":\"EMR_EC2_DefaultRole\",
                     \"SubnetId\":\"$SUBNET_ID\",
                     \"EmrManagedSlaveSecurityGroup\":\"$SLAVE_SG_ID\",
                     \"EmrManagedMasterSecurityGroup\":\"$MASTER_SG_ID\"}" \
  --service-role EMR_DefaultRole \
  --enable-debugging \
  --release-label emr-4.4.0 \
  --log-uri $LOG_URI \
  --steps "[{\"Args\":[\"/usr/bin/hdfs\",\"dfs\",\"-get\",
                     \"s3://scispark-test-code/OrgDia.jar\",
                     \"/mnt/\"],
             \"Type\":\"CUSTOM_JAR\",
             \"ActionOnFailure\":\"$STEP_FAILURE_ACTION\",
             \"Jar\":\"s3://elasticmapreduce/libs/script-runner/script-runner.jar\",
             \"Properties\":\"\",
             \"Name\":\"Custom JAR\"},
            {\"Name\":\"S3DistCp step\",
             \"Args\":[\"s3-dist-cp\",\"--s3Endpoint=s3.amazonaws.com\",
                     \"--src=s3://scispark-test-data/48hrs/\",
                     \"--dest=hdfs:///mnt/48hrs\"],
             \"ActionOnFailure\":\"CONTINUE\",
             \"Type\":\"CUSTOM_JAR\",
             \"Jar\":\"command-runner.jar\"
            },
            {\"Args\":[\"spark-submit\",
                     \"--master\", \"yarn\",
                     \"--deploy-mode\", \"client\",
                     \"--class\", \"org.dia.algorithms.mcc.MainNetcdfDFSMCC\",
                     \"/mnt/OrgDia.jar\",
                     \"yarn-client\",
                     \"2\",
                     \"20\",
                     \"ch4\",
                     \"/mnt/48hrs\"],
             \"Type\":\"CUSTOM_JAR\",
             \"ActionOnFailure\":\"$STEP_FAILURE_ACTION\",
             \"Jar\":\"command-runner.jar\",
             \"Properties\":\"\",
             \"Name\":\"Spark application\"}]" \
  --name 'My SciSpark cluster - OrgDia' \
  --instance-groups '[{"InstanceCount":1,
                       "BidPrice":".266",
                       "InstanceGroupType":"MASTER",
                       "InstanceType":"m3.xlarge",
                       "Name":"Master instance group - 1"},
                      {"InstanceCount":2,
                       "BidPrice":".266",
                       "InstanceGroupType":"CORE",
                       "InstanceType":"m3.xlarge",
                       "Name":"Core instance group - 2"}]' \
  --region us-east-1
)


# check error; if none get cluster_id
if [ $? -ne 0 ]; then
  echo "Failed to create cluster." 1>&2
  exit $STATUS
fi
cluster_id=`echo $json | grep '"ClusterId":' | cut -d'"' -f4`


# wait for it to run
date
echo -n "Waiting for cluster $cluster_id to run ... "
aws emr wait cluster-running --cluster-id $cluster_id
echo "done."
date
