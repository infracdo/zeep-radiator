# Base image
FROM ubuntu:22.04

# Set environment to non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
        libdbi-perl \
        libdbd-pg-perl \
        libdigest-md4-perl \
        libredis-perl \
        libjson-perl && \
    apt-get install -f -y && \
    apt-get clean

# Copy and install the Radiator .deb package
COPY radiator_4.23-3_all.deb /tmp/
RUN dpkg -i /tmp/radiator_4.23-3_all.deb || apt-get install -f -y

# Create config directory
RUN mkdir -p /etc/radiator

# Copy configuration and certificates
COPY radiator.conf /etc/radiator/
COPY certs/ /etc/radiator/certs/
COPY dictionary /opt/radiator/radiator/
COPY pre_session_hook.pl /etc/radiator/
COPY post_session_hook.pl /etc/radiator/
COPY post_processing_hook.pl /etc/radiator/
COPY AuthZeep.pm /opt/radiator/radiator/Radius/
COPY .env /etc/radiator

RUN chmod 644 /etc/radiator/pre_session_hook.pl \
 && chmod 644 /etc/radiator/post_session_hook.pl \
 && chmod 644 /etc/radiator/post_processing_hook.pl \
 && chmod -R 777 /opt/radiator/radiator/Radius/AuthZeep.pm \
 && mkdir -p /var/log/radiator \
 && chmod 777 /var/log/radiator

# Expose RADIUS port (default is 1812/UDP for auth, 1813/UDP for accounting)
EXPOSE 1812/udp 1813/udp

# Start Radiator in foreground with logging
#CMD ["/opt/radiator/radiator/radiusd", "-config_file", "/etc/radiator/radiator.conf", "-foreground", "-log_stdout"]
#CMD ["/opt/radiator/radiator/radiusd", "-config_file", "/etc/radiator/radiator.conf", "-foreground", "-log_stdout", "-log_dir", "/var/log/radiator"]
#CMD ["/bin/bash", "-c", "/opt/radiator/radiator/radiusd -config_file /etc/radiator/radiator.conf & tail -F /var/log/radiator/radiator.log"]
CMD ["/bin/bash", "-c", "/opt/radiator/radiator/radiusd -config_file /etc/radiator/radiator.conf & tail -F /var/log/radiator/radiator.log /var/log/radiator/session_debug.log"]