import Foundation

public class SOCKS5AuthAdapterFactory: ServerAdapterFactory {
    let username: String
    let password: String
    
    public init(_ auth: socks5Auth) {
        self.username = auth.username
        self.password = auth.password
        super.init(serverHost: auth.host, serverPort: auth.port)
    }

    override open func getAdapterFor(session: ConnectSession) -> AdapterSocket {
        let adapter = SOCKS5AuthAdapter(serverHost: serverHost, serverPort: serverPort, username: username, password: password)
        adapter.socket = RawSocketFactory.getRawSocket()
        return adapter
    }
}

class SOCKS5AuthAdapter: SOCKS5Adapter {
    let username: Data
    let password: Data
    var waitAuthResult: Bool = false

    public init(serverHost: String, serverPort: Int, username: String, password: String) {
        self.username = username.data(using: .utf8)!
        self.password = password.data(using: .utf8)!
        super.init(serverHost: serverHost, serverPort: serverPort)
        self.helloData = Data(bytes: UnsafePointer<UInt8>(([0x05, 0x01, 0x02] as [UInt8])), count: 3)
    }

    override func didConnectWith(socket: RawTCPSocketProtocol) {
        super.didConnectWith(socket: socket)

        internalStatus = .connecting // 让它继续处于 .connection 的状态，这样可以在 super.didRead 时跳过数据处理
    }

    override func didRead(data: Data, from socket: RawTCPSocketProtocol) {
        super.didRead(data: data, from: socket)

        if internalStatus == .connecting {
            if data.count != 2 { // 无论是协商认证，还是认证结果，返回字节都是 2
                disconnect()
                return
            }
            if waitAuthResult == false { // 连接成功，等待发送密码回去
                let handshake = [UInt8](data)
                if handshake[0] == 0x05 && handshake[1] == 0x02 {
                    var auth: [UInt8] = [0x01, UInt8(username.count)]
                    auth += [UInt8](username)
                    auth += [UInt8(password.count)]
                    auth += [UInt8](password)

                    write(data: Data(auth))

                    waitAuthResult = true
                    socket.readDataTo(length: 2)
                } else { // 协议失败,退出VPN
                    disconnect()
                    return
                }
            } else { // 返回了认证结果
                let authresult = [UInt8](data)
                if authresult[0] == 0x01 && authresult[1] == 0x00 {
                    // 认证成功，进入 SOCKS5Adapter.didRead 处理流程
                    internalStatus = .readingMethodResponse
                    self.didRead(data: Data(), from: socket)
                } else {
                    // 退出之前先进行保存退出原因，登录APP后就可以得知
                    disconnect()
                    exit(0)
                }
            }
            return
        }
    }
}
