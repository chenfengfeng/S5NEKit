import Foundation

open class StreamScanner {
    var receivedData: NSMutableData = NSMutableData()
    let pattern: Data
    let maximumLength: Int
    var finished = false

    var currentLength: Int {
        return receivedData.length
    }

    public init(pattern: Data, maximumLength: Int) {
        self.pattern = pattern
        self.maximumLength = maximumLength
    }

    // 我知道如果有大量NSData，这不是最有效的算法，但是由于我们只需要在http标头中找到CRLF（到目前为止），并且应该在第一个readData调用中准备好它，所以没有 需要实现一种复杂的算法，这种算法在这种情况下很可能会变慢。
    open func addAndScan(_ data: Data) -> (Data?, Data)? {
        guard finished == false else {
            return nil
        }

        receivedData.append(data)
        let startind = max(0, receivedData.length - pattern.count - data.count)
        let range = receivedData.range(of: pattern, options: .backwards, in: NSRange(location: startind, length: receivedData.length - startind))

        if range.location == NSNotFound {
            if receivedData.length > maximumLength {
                finished = true
                return (nil, receivedData as Data)
            } else {
                return nil
            }
        } else {
            finished = true
            let foundEndIndex = range.location + range.length
            return (receivedData.subdata(with: NSRange(location: 0, length: foundEndIndex)), receivedData.subdata(with: NSRange(location: foundEndIndex, length: receivedData.length - foundEndIndex)))
        }
    }
}
