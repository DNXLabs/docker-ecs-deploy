FROM dnxsolutions/aws:2.1.9-dnx1

WORKDIR /work

COPY requirements.txt .

RUN python3 -m pip install --no-cache-dir -r requirements.txt

COPY src .

ENTRYPOINT [ "python3", "-u" ]

CMD [ "/work/deploy.py" ]
