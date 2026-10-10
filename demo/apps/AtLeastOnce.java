// AtLeastOnce.java — 手動提交 offset 的 consumer:展示「處理完、提交前當機」會造成重複處理(at-least-once)。
// 用法:AtLeastOnce <topic> <group> <處理幾筆> <commit-after|crash-before-commit>
// 白話:先處理(這裡只是印出 id),處理完才提交 offset。
//   - commit-after:處理完 N 筆後提交,正常結束。
//   - crash-before-commit:處理完 N 筆,但在提交之前就當機(System.exit),模擬應用程式在處理後、提交前掛掉。
//   下次啟動會從「上次提交的位置」開始,所以那 N 筆會被再處理一次。
import java.io.FileInputStream;
import java.time.Duration;
import java.util.*;
import org.apache.kafka.clients.consumer.*;
import org.apache.kafka.common.serialization.StringDeserializer;

public class AtLeastOnce {
    public static void main(String[] a) throws Exception {
        String topic = a[0], group = a[1];
        int want = Integer.parseInt(a[2]);
        boolean crash = a[3].equals("crash-before-commit");

        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream("/clients/token-bootstrap.properties")) { p.load(in); }
        p.put("bootstrap.servers", System.getenv().getOrDefault("BOOTSTRAP", "broker1:9094,broker2:9094,broker3:9094"));
        p.put("key.deserializer", StringDeserializer.class.getName());
        p.put("value.deserializer", StringDeserializer.class.getName());
        p.put("group.id", group);
        p.put("auto.offset.reset", "earliest");
        p.put("enable.auto.commit", "false");          // 手動提交:什麼時候提交由應用程式決定
        p.put("max.poll.records", String.valueOf(want));

        List<String> done = new ArrayList<>();
        try (KafkaConsumer<String, String> c = new KafkaConsumer<>(p)) {
            c.subscribe(List.of(topic));
            while (done.size() < want) {
                for (ConsumerRecord<String, String> r : c.poll(Duration.ofSeconds(2))) {
                    done.add(r.value());                  // 「處理」:這裡只是記下 id
                    if (done.size() == want) break;
                }
            }
            System.out.println("已處理 " + done.size() + " 筆:" + done.get(0) + " 到 " + done.get(done.size() - 1));
            if (crash) {
                System.out.println("在提交 offset 之前當機(模擬)");
                Runtime.getRuntime().halt(1);
            }
            c.commitSync();
            System.out.println("已提交 offset");
        }
    }
}
