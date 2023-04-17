FROM dnxsolutions/aws:1.22.48-dnx2

WORKDIR /work

COPY src .

# RUN apk add libcurl=7.79.1-r5 \
#     && apk add curl=7.79.1-r5 \
#     && apk add git=2.32.6-r0 \
#     && apk add python3=3.9.16-r0 \
#     && apk add python3-dev=3.9.16-r0

ENTRYPOINT [ "python3", "-u" ]

CMD [ "/work/deploy.py" ]
