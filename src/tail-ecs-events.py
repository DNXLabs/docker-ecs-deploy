#!/usr/bin/env python3

import boto3, json, time, os, datetime

aws_ecs = boto3.client('ecs')

cluster_name=os.environ['CLUSTER_NAME']
app_name=os.environ['APP_NAME']

last_event = None

while True:
  try:
    response = aws_ecs.describe_services(
      cluster=cluster_name,
      services=[
        app_name
      ]
    )

    events = response['services'][0]['events']
    events_collected = []

    for event in events:
      if not last_event or event['id'] == last_event:
        break

      events_collected.insert(0, event)

    for event_collected in events_collected:
      print('%s %s' % ('{0:%Y-%m-%d %H:%M:%S %z}'.format(event_collected['createdAt']), event_collected['message']))

    last_event = events[0]['id']
    time.sleep(5)

  except Exception as e:
    print("error: " + str(e))


