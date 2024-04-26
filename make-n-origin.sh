#!/bin/bash

n_origins=$1
pink_1=3123
pink_2=3122
gray_1=3121
gray_2=3138
blue_1=3139
blue_2=3114

mkdir -p $n_origins-origins
cd $n_origins-origins
cat <<EOF > run.sh
master ()
{ 
    local regex="tpc-master";
    local pod_name=\$(kubectl get pods -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E "\$regex");
    if [ -n "\$pod_name" ]; then
        echo "\$pod_name";
    else
        echo "No pod found matching the provided regex pattern.";
    fi
}

for i in pink gray blue; do
    cd \$i
    for j in \$(ls); do kubectl apply -k \$j; sleep 1; done
    sleep 15;
    kubectl cp /tmp/x509up_u31749 \$(master):/home/x509
    kubectl exec \$(master) -- /home/gfal/run.sh $n_origins
    for k in \$(ls); do kubectl delete -k \$k; sleep 1; done
    sleep 30
    cd ..
done
EOF
for col in pink gray blue; do
mkdir -p $col

if [ $col == "pink" ]; then
    vlan1=$pink_1
    vlan2=$pink_2
    ipstart=20
elif [ $col == "gray" ]; then
    vlan1=$gray_1
    vlan2=$gray_2
    ipstart=40
else
    vlan1=$blue_1
    vlan2=$blue_2
    ipstart=60
fi

cd $col
# make tpc-master
mkdir -p tpc-master
cd tpc-master
cat <<EOF > 00-init-setup.sh
#!/bin/bash
rm -f /etc/cron.d/fetch-crl 

curl http://uaf-1.t2.ucsd.edu/dummy_ca/560061af.0 -o /etc/grid-security/certificates/560061af.0
chmod 644 /etc/grid-security/certificates/560061af.0
chown root: /etc/grid-security/certificates/560061af.0
EOF

cat <<EOF > kustomization.yaml
namespace: osg-gil

resources:
  - deployment.yaml

configMapGenerator:
  - name: configs-master
    files:
      - 00-init-setup.sh

generatorOptions:
  disableNameSuffixHash: true

commonLabels:
  app: tpc-master-loop
EOF

cat <<EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: tpc-master-loop-${col}
  name: tpc-master-loop-${col}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tpc-master-loop-${col}
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: tpc-master-loop-${col}
      annotations:
        k8s.v1.cni.cncf.io/networks: 
          '[{
              "name": "multus$vlan1",
              "ips": ["10.1.11.${ipstart}/24"],
              "gateway": ["10.1.11.1"]
          }]'
    spec:
      hostAliases:
$(
for i in $(seq 1 $n_origins); do 
  echo "      - ip: \"10.1.11.$((ipstart+i))\""
  echo "        hostnames:"
  echo "        - \"xrd-$((i)).rucio.sense.org\""
done
)
      tolerations:
      - effect: NoSchedule
        key: nautilus.io/stashcache
        operator: Exists
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - k8s-gen5-01.sdsc.optiputer.net
      containers:
      - image: aaarora/tpc-master:latest
        securityContext:
           privileged: true
        name: tpc-master-loop-${col}
        resources:
           limits:
              memory: 8Gi
              cpu: 124
           requests:
              memory: 8Gi
              cpu: 4
        volumeMounts:
        - mountPath: /etc/osg/image-init.d/00-init-setup.sh
          name: configs
          subPath: 00-init-setup.sh
      dnsPolicy: ClusterFirst
      volumes:
      - name: configs
        configMap:
          name: configs-master
          defaultMode: 420
          items:
          - key: 00-init-setup.sh
            path: 00-init-setup.sh
EOF

cd ..
for i in $(seq 1 2 $n_origins); do
# make origins
mkdir -p origin-$i
cd origin-$i
mkdir -p secrets
cp ../../../certMaker/xrd-$i.rucio.sense.org.crt secrets/xrd${i}cert.pem
cp ../../../certMaker/xrd-$i.rucio.sense.org.key secrets/xrd${i}key.pem

kubectl create --namespace osg-gil secret generic xrootd-cert-loop${i} --dry-run=client \
    --from-file=hostcert.pem=secrets/xrd${i}cert.pem \
    --from-file=hostkey.pem=secrets/xrd${i}key.pem -o yaml > secret-cert${i}.yaml

cp ../../../certMaker/xrd-$((i+1)).rucio.sense.org.crt secrets/xrd$((i+1))cert.pem
cp ../../../certMaker/xrd-$((i+1)).rucio.sense.org.key secrets/xrd$((i+1))key.pem

kubectl create --namespace osg-gil secret generic xrootd-cert-loop$((i+1)) --dry-run=client \
    --from-file=hostcert.pem=secrets/xrd$((i+1))cert.pem \
    --from-file=hostkey.pem=secrets/xrd$((i+1))key.pem -o yaml > secret-cert$((i+1)).yaml

cat <<EOF > 15-init-setup.sh 
#!/bin/bash

# remove fetch-crl so that it does NOT complain about our certs
supervisorctl stop xrootd-standalone
rm -f /etc/cron.d/fetch-crl 
rm -rf /etc/grid-security/certificates/*.r0
rm -rf /var/spool/xrootd/.xrdtls/*
supervisorctl start xrootd-standalone

# add 'user' used in gridmpafile and Authfile
useradd ddavila
useradd aaarora

# create test files
echo "Hello World" > /tmp/hello
head -c 1M /dev/random > /tmp/1M

curl http://uaf-1.t2.ucsd.edu/dummy_ca/560061af.0 -o /etc/grid-security/certificates/560061af.0
chmod 644 /etc/grid-security/certificates/560061af.0
chown root: /etc/grid-security/certificates/560061af.0
EOF

cat <<EOF > Authfile
u ddavila / a
u jbalcas / a
u aaarora / a
EOF

cat <<EOF > grid-mapfile
"/DC=ch/DC=cern/OU=Organic Units/OU=Users/CN=ddavila/CN=815177/CN=Diego Davila Foyo" ddavila
"/DC=ch/DC=cern/OU=Organic Units/OU=Users/CN=aaarora/CN=852377/CN=Aashay Arora" aaarora
"/DC=ch/DC=cern/OU=Organic Units/OU=Users/CN=jbalcas/CN=751133/CN=Justas Balcas" jbalcas
EOF

cat << EOF > kustomization.yaml
namespace: osg-gil

resources:
  - deployment1.yaml
  - deployment2.yaml
  - secret-cert${i}.yaml
  - secret-cert$((i+1)).yaml

configMapGenerator:
  - name: configs-${i}
    files:
      - xrootd-standalone.cfg
      - Authfile
      - grid-mapfile
      - 15-init-setup.sh
      - macaroon-secret

generatorOptions:
  disableNameSuffixHash: true

commonLabels:
  app: xrootd-server-loop

EOF

cat <<EOF > macaroon-secret
YZ5kWhUlkau2L/7kWYzX86QMn09klh+Nabn3tNI1v3zjuKsPm0wJtu2jtCJyLYIA
3yUnkhgQ33WX0VfOkhv2Bg==
EOF

cat <<EOF > xrootd-standalone.cfg
all.adminpath /var/spool/xrootd 
all.pidpath /run/xrootd 
xrd.port 1098
all.role server
cms.allow host * 
ofs.authorize 
acc.authdb /etc/xrootd/Authfile 
xrd.network keepalive kaparms 10m,1m,5 
xrd.timeout idle 60m 
xrd.tls /etc/grid-security/xrd/xrdcert.pem /etc/grid-security/xrd/xrdkey.pem 
xrd.tlsca certdir /etc/grid-security/certificates 
xrootd.tls capable all 
all.sitename T2_US_UCSD-TEST 
oss.localroot /mnt
sec.protocol ztn 
xrootd.seclib /usr/lib64/libXrdSec.so 
sec.protocol /usr/lib64 gsi -certdir:/etc/grid-security/certificates -cert:/etc/grid-security/xrd/xrdcert.pem -key:/etc/grid-security/xrd/xrdkey.pem -crl:try -vomsfun:libXrdVoms.so -vomsfunparms:certfmt=pem|grpopt=useall -gmapopt:trymap -gmapto:0 -gridmap:/etc/grid-security/grid-mapfile 
xrootd.chksum max 10 adler32
all.export / 

macaroons.secretkey /etc/xrootd/macaroon-secret
ofs.authlib ++ libXrdMacaroons.so

xrd.tlsca certdir /etc/grid-security/certificates
xrd.tls /etc/grid-security/xrd/xrdcert.pem /etc/grid-security/xrd/xrdkey.pem
xrootd.tls capable all

# HTTP
xrd.protocol http:1098 /usr/lib64/libXrdHttp.so
http.header2cgi Authorization authz
http.gridmap /etc/grid-security/grid-mapfile
http.exthandler xrdtpc libXrdHttpTPC.so
http.exthandler xrdmacaroons libXrdMacaroons.so
http.listingdeny yes
http.desthttps yes
http.secxtractor /usr/lib64/libXrdVoms.so

# ofs.trace open
# xrootd.trace emsg login stall redirect 
EOF

cat <<EOF > deployment1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: xrootd-server-${col}${i}
  name: xrootd-server-${col}${i}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: xrootd-server-${col}${i}
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: xrootd-server-${col}${i}
      annotations:
        k8s.v1.cni.cncf.io/networks: 
          '[{
              "name": "multus$vlan1",
              "ips": ["10.1.11.$((ipstart+i))/24"],
              "gateway": ["10.1.11.1"]
          }]'
    spec:
      hostAliases:
      - ip: "10.1.11.$((ipstart+1+i))"
        hostnames:
        - "xrd-$((i+1)).rucio.sense.org"
      tolerations:
      - effect: NoSchedule
        key: nautilus.io/stashcache
        operator: Exists
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - k8s-gen5-01.sdsc.optiputer.net
      containers:
      - image: opensciencegrid/xrootd-standalone:23-release
        securityContext:
           privileged: true
        ports:
         - containerPort: 1098
        name: xrootd-server-${col}${i}
        resources:
           limits:
              memory: 850Gi
              cpu: 128
           requests:
              memory: 64Gi
              cpu: $((128/n_origins))
        volumeMounts:
        - mountPath: /etc/xrootd/xrootd-standalone.cfg
          name: configs
          subPath: xrootd-standalone.cfg
        - mountPath: /etc/xrootd/Authfile
          name: configs
          subPath: Authfile
        - mountPath: /etc/grid-security/grid-mapfile
          name: configs
          subPath: grid-mapfile
        - mountPath: /etc/osg/image-init.d/12-init-setup.sh
          name: configs
          subPath: 15-init-setup.sh
        - mountPath: /etc/xrootd/macaroon-secret
          name: configs
          subPath: macaroon-secret
        - mountPath: /etc/grid-security/hostcert.pem
          name: cert
          subPath: hostcert.pem
        - mountPath: /etc/grid-security/hostkey.pem
          name: cert
          subPath: hostkey.pem
        - mountPath: /mnt
          name: cache-volume
      dnsPolicy: ClusterFirst
      volumes:
      - name: configs
        configMap:
          name: configs-${i}
          defaultMode: 420
          items:
          - key: xrootd-standalone.cfg
            path: xrootd-standalone.cfg
          - key: Authfile
            path: Authfile
          - key: grid-mapfile
            path: grid-mapfile
          - key: 15-init-setup.sh
            path: 15-init-setup.sh
          - key: macaroon-secret
            path: macaroon-secret
      - name: cert
        secret:
          secretName: xrootd-cert-loop${i}
          defaultMode: 0600
          items:
          - key: hostcert.pem
            path: hostcert.pem
          - key: hostkey.pem
            path: hostkey.pem
      - name: cache-volume
        hostPath:
          path: /mnt/nvme/${col}
          type: Directory
EOF

cat <<EOF > deployment2.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: xrootd-server-${col}$((i+1))
  name: xrootd-server-${col}$((i+1))
spec:
  replicas: 1
  selector:
    matchLabels:
      app: xrootd-server-${col}$((i+1))
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        app: xrootd-server-${col}$((i+1))
      annotations:
        k8s.v1.cni.cncf.io/networks: 
          '[{
              "name": "multus$vlan2",
              "ips": ["10.1.11.$(($ipstart+1+i))/24"],
              "gateway": ["10.1.11.1"]
          }]'
    spec:
      hostAliases:
      - ip: "10.1.11.$((ipstart+i))"
        hostnames:
        - "xrd-${i}.rucio.sense.org"
      tolerations:
      - effect: NoSchedule
        key: nautilus.io/stashcache
        operator: Exists
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                - k8s-gen5-02.sdsc.optiputer.net
      containers:
      - image: opensciencegrid/xrootd-standalone:23-release
        securityContext:
           privileged: true
        ports:
         - containerPort: 1098
        name: xrootd-server-${col}$((i+1))
        resources:
           limits:
              memory: 850Gi
              cpu: 128
           requests:
              memory: 64Gi
              cpu: $((128/n_origins - 2))
        volumeMounts:
        - mountPath: /etc/xrootd/xrootd-standalone.cfg
          name: configs
          subPath: xrootd-standalone.cfg
        - mountPath: /etc/xrootd/Authfile
          name: configs
          subPath: Authfile
        - mountPath: /etc/grid-security/grid-mapfile
          name: configs
          subPath: grid-mapfile
        - mountPath: /etc/osg/image-init.d/12-init-setup.sh
          name: configs
          subPath: 15-init-setup.sh
        - mountPath: /etc/xrootd/macaroon-secret
          name: configs
          subPath: macaroon-secret
        - mountPath: /etc/grid-security/hostcert.pem
          name: cert
          subPath: hostcert.pem
        - mountPath: /etc/grid-security/hostkey.pem
          name: cert
          subPath: hostkey.pem
        - mountPath: /mnt
          name: cache-volume
      dnsPolicy: ClusterFirst
      volumes:
      - name: configs
        configMap:
          name: configs-${i}
          defaultMode: 420
          items:
          - key: xrootd-standalone.cfg
            path: xrootd-standalone.cfg
          - key: Authfile
            path: Authfile
          - key: grid-mapfile
            path: grid-mapfile
          - key: 15-init-setup.sh
            path: 15-init-setup.sh
          - key: macaroon-secret
            path: macaroon-secret
      - name: cert
        secret:
          secretName: xrootd-cert-loop$((i+1))
          defaultMode: 0600
          items:
          - key: hostcert.pem
            path: hostcert.pem
          - key: hostkey.pem
            path: hostkey.pem
      - name: cache-volume
        hostPath:
          path: /mnt/nvme/${col}
          type: Directory
EOF

cd ..
done
cd ..
done