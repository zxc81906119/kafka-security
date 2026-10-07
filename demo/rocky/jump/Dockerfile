# jump host(Rocky Linux 9):Confluent 指令工具 + curl + ssh 客戶端;操作員 gary 的登入殼層就是 opmenu。
# 指令工具與 jar 直接從 cp-server 映像複製(與 RPM 安裝的路徑相同:/usr/bin/kafka-*、/usr/share/java、/etc/kafka)。
FROM confluentinc/cp-server:8.3.2 AS cp

FROM rockylinux:9
RUN dnf -y install java-21-openjdk-headless openssh-clients openssh-server sudo openssl tar which hostname procps-ng shadow-utils epel-release \
    && dnf -y install sshpass && dnf clean all && ssh-keygen -A   # sshpass(EPEL):OPMENU_SSH_AUTH=password 用
COPY --from=cp /usr/bin/kafka-* /usr/bin/
COPY --from=cp /usr/share/java /usr/share/java
COPY --from=cp /etc/kafka /etc/kafka

# 帳號:gary = 操作員(模擬接 AD 的使用者),登入殼層是選單;opbootstrap = 保管 bootstrap certificate 的專用帳號
RUN groupadd opmenu && useradd -m -G opmenu -s /opt/opmenu/opmenu.sh gary \
    && useradd -r -m -d /etc/opmenu/bootstrap -s /sbin/nologin opbootstrap \
    && mkdir -p /var/log/opmenu && chgrp opmenu /var/log/opmenu && chmod 2775 /var/log/opmenu \
    && mkdir -p /etc/kafka/secrets

# sudo 規則:gary 只能以 opbootstrap 身分執行 bootstrap 包裝腳本(緊急模式與第二人查詢用)
COPY opmenu-bootstrap /usr/local/sbin/opmenu-bootstrap
RUN chmod 755 /usr/local/sbin/opmenu-bootstrap \
    && echo 'gary ALL=(opbootstrap) NOPASSWD: /usr/local/sbin/opmenu-bootstrap' > /etc/sudoers.d/opmenu && chmod 440 /etc/sudoers.d/opmenu

# ssh 到 node:gary 的金鑰(測試用,正式環境由 AD 或金鑰管理發放)
COPY --from=keys --chown=gary:gary gary /home/gary/.ssh/id_ed25519
RUN chmod 700 /home/gary/.ssh && chmod 600 /home/gary/.ssh/id_ed25519 \
    && printf 'Host *\n  StrictHostKeyChecking accept-new\n' > /home/gary/.ssh/config && chown gary:gary /home/gary/.ssh/config

# jump host 的 sshd:opmenu 群組的人登入只能進選單(ForceCommand),不能 scp/sftp、不能轉埠;金鑰同一把(測試用)
COPY --from=keys --chown=gary:gary gary.pub /home/gary/.ssh/authorized_keys
RUN chmod 600 /home/gary/.ssh/authorized_keys && printf '\nMatch Group opmenu\n  ForceCommand /opt/opmenu/opmenu.sh\n  AllowTcpForwarding no\n  AllowAgentForwarding no\n  X11Forwarding no\n  PermitTunnel no\n' >> /etc/ssh/sshd_config

COPY setup.sh /usr/local/sbin/opmenu-setup
RUN chmod 755 /usr/local/sbin/opmenu-setup
CMD ["/bin/sh", "-c", "/usr/local/sbin/opmenu-setup && exec sleep infinity"]
