// Producer.java — 送出 N 筆訊息(內容 "id-<序號>"),印出「確認成功幾筆、失敗幾筆」。
// 用法:Producer <topic> <筆數> <每秒筆數> <idempotent:true|false> [requestTimeoutMs]
// 白話:用來觀察 producer 遇到 broker 暫停(逾時重送)時,會不會寫出重複的訊息。
//   acks=all、retries 放寬、max.in.flight=5(預設值);requestTimeoutMs 設短一點才容易在 broker 暫停時觸發重送。
import java.io.FileInputStream;
import java.util.Properties;
import java.util.concurrent.atomic.AtomicInteger;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;

public class Producer {
    public static void main(String[] a) throws Exception {
        String topic = a[0];
        int count = Integer.parseInt(a[1]);
        int perSec = Integer.parseInt(a[2]);
        boolean idempotent = Boolean.parseBoolean(a[3]);
        int requestTimeout = a.length > 4 ? Integer.parseInt(a[4]) : 2000;

        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream("/clients/token-bootstrap.properties")) { p.load(in); }
        p.put("bootstrap.servers", System.getenv().getOrDefault("BOOTSTRAP", "broker1:9094,broker2:9094,broker3:9094"));
        p.put("key.serializer", StringSerializer.class.getName());
        p.put("value.serializer", StringSerializer.class.getName());
        p.put("acks", "all");
        p.put("enable.idempotence", String.valueOf(idempotent));
        p.put("retries", String.valueOf(Integer.MAX_VALUE));
        p.put("max.in.flight.requests.per.connection", "5");
        p.put("request.timeout.ms", String.valueOf(requestTimeout));
        p.put("delivery.timeout.ms", "60000");
        p.put("linger.ms", "0");

        AtomicInteger ok = new AtomicInteger(), failed = new AtomicInteger();
        long pauseNanos = 1_000_000_000L / Math.max(1, perSec);
        try (KafkaProducer<String, String> producer = new KafkaProducer<>(p)) {
            for (int i = 0; i < count; i++) {
                producer.send(new ProducerRecord<>(topic, null, "id-" + i), (m, e) -> {
                    if (e == null) ok.incrementAndGet(); else failed.incrementAndGet();
                });
                Thread.sleep(pauseNanos / 1_000_000L, (int) (pauseNanos % 1_000_000L));
            }
            producer.flush();
        }
        System.out.println("producer idempotent=" + idempotent + " 確認成功=" + ok.get() + " 失敗=" + failed.get());
    }
}
