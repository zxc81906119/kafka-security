# 「node」(Rocky Linux 9 + systemd + sshd):只用來測 jump host 的 ssh + sudo + systemctl/journalctl 流程。
# 服務是假的(confluent-server、confluent-control-center 兩個單元,只會定時寫日誌),真正的 Kafka 仍是 demo 的容器。
FROM rockylinux:9
RUN dnf -y install systemd openssh-server sudo procps-ng findutils && dnf clean all \
    && systemctl enable sshd

# 假服務
COPY fake-service /usr/local/bin/fake-service
RUN chmod 755 /usr/local/bin/fake-service \
    && for s in confluent-server confluent-control-center; do printf '[Unit]\nDescription=%s (fake)\n[Service]\nExecStart=/usr/local/bin/fake-service %s\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' "$s" "$s" > /etc/systemd/system/$s.service; systemctl enable $s; done

# data directory 與應用程式日誌(含幾個很舊的檔案給「清理日誌」測)
RUN mkdir -p /var/lib/kafka/data /var/log/kafka && dd if=/dev/zero of=/var/lib/kafka/data/00000.log bs=1M count=8 2>/dev/null \
    && for d in 1 10 20 40; do touch -d "$d days ago" /var/log/kafka/server.log.$d; done

# 操作員 gary:ssh 金鑰登入;sudo 只開放指定指令
COPY opmenu-clean-logs /usr/local/sbin/opmenu-clean-logs
RUN chmod 755 /usr/local/sbin/opmenu-clean-logs && useradd -m gary && echo 'gary:gary-pw' | chpasswd && mkdir -p /home/gary/.ssh   # 密碼與 demo 的 AD 相同,模擬 node 接 AD
COPY --from=keys gary.pub /home/gary/.ssh/authorized_keys
RUN chown -R gary:gary /home/gary/.ssh && chmod 700 /home/gary/.ssh && chmod 600 /home/gary/.ssh/authorized_keys \
    && printf 'gary ALL=(root) NOPASSWD: /usr/bin/systemctl restart confluent-*, /usr/bin/systemctl status confluent-*, /usr/bin/journalctl, /usr/local/sbin/opmenu-clean-logs\n' > /etc/sudoers.d/opmenu && chmod 440 /etc/sudoers.d/opmenu

CMD ["/sbin/init"]
