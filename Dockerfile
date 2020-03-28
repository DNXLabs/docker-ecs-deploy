FROM dnxsolutions/aws:1.17.14-dnx3

RUN apk --no-cache update && \
    apk --no-cache add python3 && \
    rm -rf /var/cache/apk/*

RUN pip3 install --no-cache --upgrade boto3

ADD src .

RUN chmod +x deploy.sh task-deploy.sh run-task.sh cutover.sh tail-task-logs.py

ENTRYPOINT [ "/bin/bash", "-c" ]

CMD [ "/work/deploy.sh" ]
