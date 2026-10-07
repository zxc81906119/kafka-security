set -e; cd /w
openssl req -x509 -newkey rsa:2048 -nodes -keyout root.key -out root.pem -days 30 -subj "/CN=Test AD Root CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout inter.key -out inter.csr -subj "/CN=Test AD Issuing CA" 2>/dev/null
printf "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n" > inter.ext
openssl x509 -req -in inter.csr -CA root.pem -CAkey root.key -CAcreateserial -out inter.pem -days 30 -extfile inter.ext 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/CN=ldaps-proxy" 2>/dev/null
printf "subjectAltName=DNS:ldaps-proxy\nextendedKeyUsage=serverAuth\n" > leaf.ext
openssl x509 -req -in leaf.csr -CA inter.pem -CAkey inter.key -CAcreateserial -out leaf.pem -days 30 -extfile leaf.ext 2>/dev/null
chmod 644 *.key
openssl verify -CAfile root.pem -untrusted inter.pem leaf.pem
