#!/usr/bin/env python3

import boto3, json, time, os, datetime

aws_ecs = boto3.client('ecs')

cluster_name=os.environ['CLUSTER_NAME']
app_name=os.environ['APP_NAME']
task_arn=os.environ['TASK_ID']

last_event = None

while True:
  try:
    response = aws_ecs.describe_services(
      cluster=cluster_name,
      tasks=[
        task_arn
      ]
    )
    logs = boto3.client('logs')
    last_status = response['tasks'][0]['lastStatus']
    events_collected = []

    for status in last_status:
      print('Task status %s', status)
    
    task_arn=os.environ['TASK_ID']
    
    logStream = logs.get_log_events(
                    logGroupName='/ecs/'+cluster_name+'/'+app_name,
                    logStreamName='string',
                    startFromHead=True)
    for log in logStream:
      print('%s\t%s' % ('{0:%Y-%m-%d %H:%M:%S %z}'.format(log['createdAt']), log['message']))

    last_event = events[0]['id']

    if not status == 'STOPPDED':
        break
    time.sleep(1)

  except Exception as e:
    print("error: " + str(e))


