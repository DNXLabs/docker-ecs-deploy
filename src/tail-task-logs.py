#!/usr/bin/env python3

import boto3, json, time, os, datetime

aws_ecs = boto3.client('ecs')

cluster_name=os.environ['CLUSTER_NAME']
app_name=os.environ['APP_NAME']
task_arn=os.environ['TASK_ID']
app_command=os.environ['DEFAULT_COMMAND']
task_number=task_arn.split(":task/",1)[1]  #get the task number id
last_event = None

while True:
  try:
    response = aws_ecs.describe_tasks(
      cluster=cluster_name,
      tasks=[task_arn])
    logs = boto3.client('logs')
    task_status = response['tasks'][0]['lastStatus']
    events_collected = []
    print('Task status', task_status)
    logGroupName='/ecs/'+cluster_name+'/'+app_name
    print('Searching logs for ', logGroupName)
    time.sleep(4)
    logStreams = logs.describe_log_streams(
        logGroupName=logGroupName,
        logStreamNamePrefix=app_name+'/'+app_command+'/'+app_name+'/'+task_number,
        limit=1,
        descending=True)
    for stream in logStreams['logStreams']:      
      streamName=stream['logStreamName']
      print('log Streams', streamName)  
      logStreamEvents = logs.get_log_events(
                      logGroupName=logGroupName,
                      logStreamName=streamName,
                      startFromHead=True)
      for log in logStreamEvents['events']:
        print(log['message'])
    if task_status == 'STOPPED':
      break
    time.sleep(10)

  except Exception as e:
    print("error: " + str(e))
    break


