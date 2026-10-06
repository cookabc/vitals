/// 固定容量的历史采样队列，超出容量时丢弃最旧的样本。
struct Ring<Value> {
    private(set) var values: [Value] = []
    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
    }

    mutating func append(_ value: Value) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }
}
