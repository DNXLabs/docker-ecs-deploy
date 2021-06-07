FROM dnxsolutions/aws:2.1.9-dnx1

COPY src .

RUN chmod +x *.sh *.py

ENTRYPOINT [ "/bin/bash", "-c" ]

CMD [ "/work/deploy.sh" ]
