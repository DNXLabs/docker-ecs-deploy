FROM dnxsolutions/aws:2.1.9-dnx1

RUN apk --no-cache update && \
    apk --no-cache add python3 && \
    rm -rf /var/cache/apk/*

RUN pip3 install --no-cache --upgrade boto3==1.17.42

ADD src .

RUN chmod +x *.sh *.py

ENTRYPOINT [ "/bin/bash", "-c" ]

CMD [ "/work/deploy.sh" ]
