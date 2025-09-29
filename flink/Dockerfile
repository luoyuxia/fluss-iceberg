FROM flink:1.20.0-scala_2.12-java17
USER root
RUN apt-get update
RUN apt install tree

# Copy sql-client script
COPY bin/* /opt/sql-client/

WORKDIR /opt/sql-client
ENV SQL_CLIENT_HOME=/opt/sql-client

COPY lib/* /opt/sql-client/lib/
COPY sql/* /opt/sql-client/sql/
COPY lib/* /opt/flink/lib/
COPY opt/* /opt/flink/opt/

RUN ["chmod", "+x", "/opt/sql-client/sql-client"]