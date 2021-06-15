FROM dnxsolutions/aws:2.1.9-dnx1

WORKDIR /work

COPY src .

ENTRYPOINT [ "/bin/bash", "-c" ]

CMD [ "/work/deploy.sh" ]