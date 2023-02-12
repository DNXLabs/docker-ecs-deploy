#!/usr/bin/env python3

import boto3, json, time, os, datetime, sys

aws_ecs = boto3.client('ecs')
logs = boto3.client('logs')

cluster_name=os.environ['CLUSTER_NAME']
app_name=os.environ['APP_NAME']
task_arn=sys.argv[1]

task_id=task_arn.split("/")[-1]  #get the task number id (without the cluster name)
last_event = None
log_group_name='/ecs/'+cluster_name+'/'+app_name
log_stream_prefix = None
log_stream_events = None

print("======== TASK LOGS ========")

while True:
  try:
    if log_stream_prefix is None:
      try:
        log_streams = logs.describe_log_streams(logGroupName=log_group_name, orderBy='LastEventTime', descending=True, limit=1)
      except:
        raise Exception("The specified log group does not exist")

      if len(log_streams['logStreams']) != 0:
        log_stream_prefix='/'.join(log_streams['logStreams'][0]['logStreamName'].split('/')[:-1])
        extra_args = {
          'logGroupName': log_group_name,
          'logStreamName': log_stream_prefix+'/'+task_id,
          'startFromHead': True
        }
    else:
      try:
        log_stream_events = logs.get_log_events(**extra_args)
       
        for event in log_stream_events['events']:
          print("%s" % (event['message']))

        if 'nextToken' not in extra_args or log_stream_events['nextForwardToken'] != extra_args['nextToken']:
          extra_args['nextToken'] = log_stream_events['nextForwardToken']  
      
      except:
        print('No logs sent to CloudWatch')
       
      response = aws_ecs.describe_tasks(
        cluster=cluster_name,
        tasks=[task_arn])
        
      if response['tasks'][0]['lastStatus'] == "STOPPED":
        print("======== TASK STOPPED ========")
        print("Task ID:        %s" % task_id)
        print("Task ARN:       %s" % task_arn)
        print("Service Name:   %s" % app_name)
        print("Cluster Name:   %s" % cluster_name)
        if 'startedAt' in response['tasks'][0]:
          print("Started at:     %s" % response['tasks'][0]['startedAt'])
        print("Stopped at:     %s" % response['tasks'][0]['stoppedAt'])
        print("Stopped Reason: %s" % response['tasks'][0]['stoppedReason'])
        if 'stopCode' in response['tasks'][0]:
          print("Stop Code:      %s" % response['tasks'][0]['stopCode'])
        print("")
        break

  except logs.exceptions.ResourceNotFoundException as e:
    time.sleep(5)
    continue

  except Exception as e:
    print("Error: " + str(e))
    break

