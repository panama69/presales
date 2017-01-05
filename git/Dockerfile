FROM ubuntu:16.04
MAINTAINER Sven Dowideit <SvenDowideit@docker.com>

RUN apt-get update && apt-get install -y openssh-server git curl
RUN mkdir /var/run/sshd

RUN echo 'root:hpe' | chpasswd
RUN sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

ENV GIT_HOME /opt/gitrepo
RUN mkdir -p "$GIT_HOME" && cd "$GIT_HOME" && \
    git clone https://github.com/panama69/HelloWorld.git && \
    git clone https://github.com/panama69/deleteme.git

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
