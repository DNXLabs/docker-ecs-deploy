FROM dnxsolutions/aws:2.1.9-dnx1

WORKDIR /work

COPY src .

RUN python3 -m pip install --no-cache-dir pip==23.1.2 \
    && pip install --no-cache-dir awscli==1.27.142 \
    && pip install --no-cache-dir botocore==1.29.142 \
    && pip install --no-cache-dir boto3==1.26.142

ENTRYPOINT [ "python3", "-u" ]

CMD [ "/work/deploy.py" ]
