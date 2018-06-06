#!/bin/bash

set -e

: "${SLAVE_IP:?Env variable SLAVE_IP must be set and not empty}"
: "${BASE_DOMAIN:?Env variable BASE_DOMAIN must be set and not empty}"
: "${ZONE_SUBDOMAIN:?Env variable ZONE_SUBDOMAIN must be set and not empty}"
: "${API_SUBDOMAIN:?Env variable API_SUBDOMAIN must be set and not empty}"
: "${API_ELB:?Env variable API_ELB must be set and not empty}"
: "${UPSTREAM_DNS:?Env variable UPSTREAM_DNS must be set and not empty}"
: "${FORWARDER:?Env variable FORWARDER must be set and not empty}"

PRIVATE_IP=$(ip addr show eth0 | grep -Po 'inet \K[\d.]+')

grep -qF "${PRIVATE_IP} kns1.${BASE_DOMAIN} kns1" /etc/hosts || echo "${PRIVATE_IP} kns1.${BASE_DOMAIN} kns1" >> /etc/hosts

echo "kns1" > /etc/hostname
hostname -F /etc/hostname

cat > /etc/named.conf <<EOF
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//
// See the BIND Administrator's Reference Manual (ARM) for details about the
// configuration located in /usr/share/doc/bind-{version}/Bv9ARM.html

acl "trusted" {
	${PRIVATE_IP};
	${SLAVE_IP};
	${UPSTREAM_DNS}
};

options {
	listen-on port 53 { 127.0.0.1; ${PRIVATE_IP}; };
	listen-on-v6 port 53 { ::1; };
	directory 	"/var/named";
	dump-file 	"/var/named/data/cache_dump.db";
	statistics-file "/var/named/data/named_stats.txt";
	memstatistics-file "/var/named/data/named_mem_stats.txt";
	allow-query     { trusted; };

	/*
	 - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.  - If you are building a RECURSIVE (caching) DNS server, you need to enable recursion.
	 - If your recursive DNS server has a public IP address, you MUST enable access
	   control to limit queries to your legitimate users. Failing to do so will
	   cause your server to become part of large scale DNS amplification
	   attacks. Implementing BCP38 within your network would greatly
	   reduce such attack surface
	*/
	recursion yes;
	allow-transfer { ${SLAVE_IP}; };

    forwarders { ${FORWARDER}; };

	dnssec-enable no;
	dnssec-validation no;

	/* Path to ISC DLV key */
	bindkeys-file "/etc/named.iscdlv.key";

	managed-keys-directory "/var/named/dynamic";

	pid-file "/run/named/named.pid";
	session-keyfile "/run/named/session.key";
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
	type hint;
	file "named.ca";
};

include "/etc/named.rfc1912.zones";
include "/etc/named.root.key";
include "/etc/named/named.conf.local";
EOF

cat > /etc/named/named.conf.local <<EOF
zone "${ZONE_SUBDOMAIN}.${BASE_DOMAIN}" {
	type master;
	file "/etc/named/zones/db.${ZONE_SUBDOMAIN}.${BASE_DOMAIN}";
	allow-transfer { ${SLAVE_IP}; };
};
EOF

if [ ! -d /etc/named/zones ]; then
	mkdir /etc/named/zones
fi
cat > /etc/named/zones/db.${ZONE_SUBDOMAIN}.${BASE_DOMAIN} <<EOF
;
; BIND data file for local loopback interface
;
\$ORIGIN ${ZONE_SUBDOMAIN}.${BASE_DOMAIN}.
\$TTL	604800
@	IN	SOA	kns1.${BASE_DOMAIN}. kadmin.${BASE_DOMAIN}. (
			      5		; Serial
			 604800		; Refresh
			  86400		; Retry
			2419200		; Expire
			 604800 )	; Negative Cache TTL
;
; Name servers
	IN	NS	kns1.${BASE_DOMAIN}.
	IN	NS	kns2.${BASE_DOMAIN}.
; A records for name servers
kns1	IN	A	${PRIVATE_IP}
kns2	IN	A	${SLAVE_IP}
;
${API_SUBDOMAIN}	IN	CNAME	${API_ELB}.
EOF

chown root:named /etc/named.conf
chown -R root:named /etc/named

named-checkconf

named-checkzone ${ZONE_SUBDOMAIN}.${BASE_DOMAIN} /etc/named/zones/db.${ZONE_SUBDOMAIN}.${BASE_DOMAIN}

systemctl restart named
systemctl enable named

exit 0

