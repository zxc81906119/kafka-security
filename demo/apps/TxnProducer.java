// TxnProducer.java — 交易 producer:一次寫入 N 筆,然後提交(commit)或放棄(abort)。
// 用法:TxnProducer <topic> <筆數> <commit|abort> [內容前綴]
// 白話:交易讓「一批訊息要嘛全部可見、要嘛全部不可見」。abort 的訊息仍然寫在 log 裡,
//   但 read_committed 的 consumer 讀不到;read_uncommitted 的 consumer 讀得到。
import java.io.FileInputStream;
import java.util.Properties;
import org.apache.kafka.clients.producer.*;
import org.apache.kafka.common.serialization.StringSerializer;

public class TxnProducer {
    public static void main(String[] a) throws Exception {
        String topic = a[0];
        int count = Integer.parseInt(a[1]);
        boolean commit = a[2].equals("commit");
        String prefix = a.length > 3 ? a[3] : "txn";

        Properties p = new Properties();
        try (FileInputStream in = new FileInputStream("/clients/token-bootstrap.properties")) { p.load(in); }
        p.put("bootstrap.servers", System.getenv().getOrDefault("BOOTSTRAP", "broker1:9094,broker2:9094,broker3:9094"));
        p.put("key.serializer", StringSerializer.class.getName());
        p.put("value.serializer", StringSerializer.class.getName());
        p.put("transactional.id", "demo-txn-" + prefix);   // 交易 id:同一個 id 代表同一個邏輯 producer(用來隔離舊的實例)
        try (KafkaProducer<String, String> producer = new KafkaProducer<>(p)) {
            producer.initTransactions();
            producer.beginTransaction();
            for (int i = 0; i < count; i++) producer.send(new ProducerRecord<>(topic, null, prefix + "-" + i));
            producer.flush();                                // 先確保訊息真的送到 broker;沒 flush 就 abort,送不出去的訊息會被直接丟掉,根本沒寫進 log
            if (commit) { producer.commitTransaction(); System.out.println("交易已提交(commit):" + count + " 筆"); }
            else        { producer.abortTransaction();  System.out.println("交易已放棄(abort):" + count + " 筆"); }
        }
    }
}
