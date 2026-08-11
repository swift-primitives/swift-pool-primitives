struct Unique: ~Copyable {
    struct Result: ~Copyable {
        let value: Int
    }

    var value: Int

    init(value: Int) {
        self.value = value
    }
}
