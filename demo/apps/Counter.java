// Counter.java — 從頭讀完一個 topic,數「總筆數、不重複筆數、重複筆數」。
// 用法:Counter <topic> [read_committed|read_uncommitted]
// 白話:判斷 producer 有沒有寫出重複的訊息(內容 id-<序號> 不該重複),或交易的 abort 訊息看不看得到。
import java.io.FileInputStream;
import java.time.Duration;
import java.util.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.common.serialization.StringDeserializer;

public class Counter {
    public static void main(String[] a) throws Exception {
        String topic = a[0];
        String isolation = a.length > 1 ? a[1] : "read_committed";
        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream("/clients/token-bootstrap.properties")) { p.load(in); }
        p.put("bootstrap.servers", System.getenv().getOrDefault("BOOTSTRAP", "broker1:9094,broker2:9094,broker3:9094"));
        p.put("key.deserializer", StringDeserializer.class.getName());
        p.put("value.deserializer", StringDeserializer.class.getName());
        p.put("group.id", "counter-" + UUID.randomUUID());
        p.put("auto.offset.reset", "earliest");
        p.put("enable.auto.commit", "false");
        p.put("isolation.level", isolation);

        Set<String> distinct = new HashSet<>();
        int total = 0, idle = 0;
        try (KafkaConsumer<String, String> c = new KafkaConsumer<>(p)) {
            c.subscribe(List.of(topic));
            while (idle < 4) {                         // 連續 4 次(約 8 秒)沒有新資料就當讀完
                ConsumerRecords<String, String> recs = c.poll(Duration.ofSeconds(2));
                if (recs.isEmpty()) idle++; else idle = 0;
                for (ConsumerRecord<String, String> r : recs) { total++; distinct.add(r.value()); }
            }
        }
        System.out.println("counter isolation=" + isolation + " 總筆數=" + total + " 不重複=" + distinct.size() + " 重複=" + (total - distinct.size()));
    }
}
