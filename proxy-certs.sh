#!/bin/bash -xe
#
# Prepare a VM for a kube certificate proxy
#
PROJECTDIR=/home/mrogers/projects/apache-cert-proxy
CERTDIR=${PROJECTDIR}/config
TODIR=${PROJECTDIR}/certs
IDFILE=/home/mrogers/vagrant/cent7/.vagrant/machines/default/virtualbox/private_key
PROXY_IP=192.168.23.11
MASTER_IP=10.13.129.12

while [ "$1" != "" ]; do
	case "$1" in
		-c | --no-certs )
			nocert=1
			shift
			;;
		-t | --no-test )
			notest=1
			shift
			;;
		-h | --no-http )
			nohttp=1
			shift
			;;
		-p | --proxy-cert )
			proxycert=1
			shift
			;;
		*)
			break
			;;
	esac
done

if [ "${proxycert}" = "1" ]; then
	# create server certificate with proxy IP
	oc adm ca create-server-cert --signer-cert=${CERTDIR}/ca.crt --signer-key=${CERTDIR}/ca.key --signer-serial=${CERTDIR}/ca.serial.txt --hostnames="proxy.example.com","${PROXY_IP}","kubernetes","kubernetes.default","kubernetes.default.svc","kubernetes.default.svc.cluster.local","localhost","openshift","openshift.default","openshift.default.svc","openshift.default.svc.cluster.local","127.0.0.1","172.17.0.1","172.30.0.1","192.168.124.1","192.168.23.1","192.168.70.1","${MASTER_IP}" --cert=${CERTDIR}/master.server.crt --key=${CERTDIR}/master.server.key
	exit 0
fi

# run after localup
if [ "${nocert}" != "1" ]; then
	# copy certs to proxy
	rm -rf ${TODIR}/*.crt
	rm -rf ${TODIR}/*.key
	cp ${CERTDIR}/ca.crt ${TODIR}/
	cp ${CERTDIR}/frontproxy-ca.crt ${TODIR}/
	cp ${CERTDIR}/openshift-aggregator.crt ${TODIR}/
	cat ${CERTDIR}/openshift-aggregator.crt > ${TODIR}/proxy-client.crt
	cat ${CERTDIR}/openshift-aggregator.key >> ${TODIR}/proxy-client.crt
	# cat ${CERTDIR}/master.proxy-client.crt > ${TODIR}/proxy-cert-key.crt
	# cat ${CERTDIR}/master.proxy-client.key >> ${TODIR}/proxy-cert-key.crt
	oc adm ca create-server-cert --signer-cert=${CERTDIR}/ca.crt --signer-key=${CERTDIR}/ca.key --signer-serial=${CERTDIR}/ca.serial.txt --hostnames="proxy.example.com","${PROXY_IP}" --cert=${TODIR}/cert-proxy-server.crt --key=${TODIR}/cert-proxy-server.key
	# sudo chown -R mrogers:mrogers ${TODIR}
	scp -i ${IDFILE} -r ${TODIR} vagrant@${PROXY_IP}:.
	ssh -i ${IDFILE} vagrant@${PROXY_IP} sudo cp -r certs/* /etc/pki/tls/certs/proxy/
fi
if [ "${nohttp}" != "1" ]; then
	scp -i ${IDFILE} ${PROJECTDIR}/openshift-proxy.conf vagrant@${PROXY_IP}:openshift-proxy.conf
	ssh -i ${IDFILE} vagrant@${PROXY_IP} sudo cp openshift-proxy.conf /etc/httpd/conf.d/openshift-proxy.conf
	ssh -i ${IDFILE} vagrant@${PROXY_IP} "sudo rm -f /var/log/httpd/error_log"
	sleep 2
	ssh -i ${IDFILE} vagrant@${PROXY_IP} sudo systemctl restart httpd
fi
if [ "${notest}" != "1" ]; then
	curl -k -E ${CERTDIR}/openshift-aggregator.crt --key ${CERTDIR}/openshift-aggregator.key -X GET -H 'Content-Type: application/json' "https://${PROXY_IP}:443"
	ssh -i ${IDFILE} vagrant@${PROXY_IP} sudo cat /var/log/httpd/error_log
fi
