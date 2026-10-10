// RebalanceWatch.java — 加入 consumer group 並印出每次 rebalance 的事件(哪些分區被收回、哪些被指派)。
// 用法:RebalanceWatch <topic> <group> <eager|cooperative> <執行幾秒> [靜態成員 id]
// 白話:
//   - eager(預設的 range / roundrobin):rebalance 時所有成員先交出全部分區,再重新分配(整個群組暫停)。
//   - cooperative(CooperativeStickyAssignor):只收回「需要換人」的分區,其他分區持續消費。
//   - 有靜態成員 id(group.instance.id):在 session.timeout 內重啟,不會觸發 rebalance。
import java.io.FileInputStream;
import java.time.Duration;
import java.util.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.common.TopicPartition;
import org.apache.kafka.common.serialization.StringDeserializer;

public class RebalanceWatch {
    public static void main(String[] a) throws Exception {
        String topic = a[0], group = a[1];
        boolean cooperative = a[2].equals("cooperative");
        long runMs = Long.parseLong(a[3]) * 1000L;
        String instanceId = a.length > 4 ? a[4] : null;
        String me = instanceId != null ? instanceId : System.getenv().getOrDefault("HOSTNAME", "consumer");

        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream("/clients/token-bootstrap.properties")) { p.load(in); }
        p.put("bootstrap.servers", System.getenv().getOrDefault("BOOTSTRAP", "broker1:9094,broker2:9094,broker3:9094"));
        p.put("key.deserializer", StringDeserializer.class.getName());
        p.put("value.deserializer", StringDeserializer.class.getName());
        p.put("group.id", group);
        p.put("auto.offset.reset", "earliest");
        p.put("partition.assignment.strategy", cooperative
            ? "org.apache.kafka.clients.consumer.CooperativeStickyAssignor"
            : "org.apache.kafka.clients.consumer.RangeAssignor");
        p.put("group.protocol", "classic");                // 8.x 預設可能是新協定;這裡要比較的是 classic 的兩種 assignor
        if (instanceId != null) { p.put("group.instance.id", instanceId); p.put("session.timeout.ms", "45000"); }

        long t0 = System.currentTimeMillis();
        try (KafkaConsumer<String, String> c = new KafkaConsumer<>(p)) {
            c.subscribe(List.of(topic), new ConsumerRebalanceListener() {
                public void onPartitionsRevoked(Collection<TopicPartition> ps) { log(t0, me, "REVOKED  " + fmt(ps)); }
                public void onPartitionsAssigned(Collection<TopicPartition> ps) { log(t0, me, "ASSIGNED " + fmt(ps)); }
                public void onPartitionsLost(Collection<TopicPartition> ps) { log(t0, me, "LOST     " + fmt(ps)); }
            });
            while (System.currentTimeMillis() - t0 < runMs) c.poll(Duration.ofMillis(500));
        }
    }
    static String fmt(Collection<TopicPartition> ps) {
        List<Integer> l = new ArrayList<>(); for (TopicPartition tp : ps) l.add(tp.partition()); Collections.sort(l); return l.toString();
    }
    static void log(long t0, String who, String msg) { System.out.println(String.format("[%2ds] %-10s %s", (System.currentTimeMillis() - t0) / 1000, who, msg)); }
}
