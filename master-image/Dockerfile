FROM opensciencegrid/software-base:23-el8-release

RUN yum -y install gfal2-util gfal2-all psmisc

ENV X509_USER_PROXY=/home/x509

COPY gfal /home/gfal
