FROM dnxsolutions/aws:1.22.48-dnx2

WORKDIR /work

COPY src .

RUN apk --no-cache add libcurl=7.79.1-r5 \
    && apk --no-cache add curl=7.79.1-r5 \
    && apk --no-cache add git=2.32.6-r0 \
    && apk --no-cache add python3=3.9.16-r0 \
    && apk --no-cache add python3-dev=3.9.16-r0

ENTRYPOINT [ "python3", "-u" ]

CMD [ "/work/deploy.py" ]
