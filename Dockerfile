FROM dnxsolutions/aws:1.22.48

WORKDIR /work

COPY src .

ENTRYPOINT [ "/bin/bash", "-c" ]

CMD [ "/work/deploy.sh" ]