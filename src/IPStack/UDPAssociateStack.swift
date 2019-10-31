import Foundation
import CocoaLumberjackSwift

public class SOCKS5AssociateAdapter: AdapterSocket {
    public var host: String?    // 这两个变量是 UDP Associate 命令后返回的
    public var port: Int?       // 供建立 UWUDPSocket 使用
    enum SOCKS5AssociateStatus {
        case invalid,
        connecting,
        readingMethodResponse,
        readingAuthResponse,
        readingAssociateAddr
    }
    public let serverHost: String
    public let serverPort: Int
    let username: Data?
    let password: Data?
    var helloData: Data
    let associateData = Data([0x05, 0x03 , 0x00 , 0x01 ,
                                0x00, 0x00, 0x00, 0x00,
                                0x00, 0x00 ])

    public enum ReadTag: Int {
        case methodResponse = -20000, connectResponseFirstPart, connectResponseSecondPart
    }

    public enum WriteTag: Int {
        case open = -21000, connectIPv4, connectIPv6, connectDomainLength, connectPort
    }

    var internalStatus: SOCKS5AssociateStatus = .invalid

    // 如果没有传入 username, password 则不走认证；否则发送认证请求
    public init(serverHost: String, serverPort: Int, username: String? = nil, password: String? = nil) {
        self.serverHost = serverHost
        self.serverPort = serverPort
        if let u = username {
            self.username = u.data(using: .utf8)
        } else {
            self.username = nil
        }
        if let p = password {
            self.password = p.data(using: .utf8)
        } else {
            self.password = nil
        }
        if username != nil && password != nil {
            helloData = Data(bytes: UnsafePointer<UInt8>(([0x05, 0x01, 0x02] as [UInt8])), count: 3)
        } else {
            helloData = Data(bytes: UnsafePointer<UInt8>(([0x05, 0x01, 0x00] as [UInt8])), count: 3)
        }
        super.init()
    }

    public override func openSocketWith(session: ConnectSession) {
        super.openSocketWith(session: session)

        guard !isCancelled else {
            return
        }

        do {
            internalStatus = .connecting
            try socket.connectTo(host: serverHost, port: serverPort, enableTLS: false, tlsSettings: nil)
        } catch {}
    }

    public override func didConnectWith(socket: RawTCPSocketProtocol) {
        super.didConnectWith(socket: socket)

        write(data: helloData)
        internalStatus = .readingMethodResponse
        socket.readDataTo(length: 2)
    }

    public override func didRead(data: Data, from socket: RawTCPSocketProtocol) {
        super.didRead(data: data, from: socket)

        switch internalStatus {
        case .readingMethodResponse:
            if data[1] == 0x02 {
                var auth: [UInt8] = [0x01, UInt8(username!.count)]
                auth += [UInt8](username!)
                auth += [UInt8(password!.count)]
                auth += [UInt8](password!)

                write(data: Data(auth))

                internalStatus = .readingAuthResponse
                socket.readDataTo(length: 2)
            } else {
                write(data: associateData)

                internalStatus = .readingAssociateAddr
                socket.readDataTo(length: 10)
            }
        case .readingAuthResponse:
            if data[0] == 0x01 && data[1] == 0x00 {
                write(data: associateData)

                internalStatus = .readingAssociateAddr
                socket.readDataTo(length: 10)
            } else {
                disconnect()
                return
            }
        case .readingAssociateAddr:
            host = "\(data[4]).\(data[5]).\(data[6]).\(data[7])"
            port = Int(data[8]) * 256 + Int(data[9])

            // TODO, delegate.debuffer(...) 如果有
        default:
            return
        }
    }
}

public class UDPAssociateSession: NSObject, SocketDelegate {
    public func didConnectWith(adapterSocket: AdapterSocket) {
        DDLogInfo("UDPAssociateAgent connect")
    }

    public func didDisconnectWith(socket: SocketProtocol) {
        // 实践中发现 NWTCPConnection 无法检测到对方 Server reset
        // 应该想别的机制来检测中断
        DDLogInfo("UDPAssociateAgent disconnect, 该 connectionInfo 不能再使用了，需要重新初始化 socket")
    }

    public func didRead(data: Data, from: SocketProtocol) {
    }

    public func didWrite(data: Data?, by: SocketProtocol) {
    }

    public func didBecomeReadyToForwardWith(socket: SocketProtocol) {
    }

    public func didReceive(session: ConnectSession, from: ProxySocket) {
    }

    public func updateAdapterWith(newAdapter: AdapterSocket) {
    }

    // 每一个新的 UDP 目标，或者说一个 session (需要维持一段时间的往来数据交互)
    // 都需要保持一个 UDP Associate CMD 的 TCP 连接 ---- 这里是 agent 变量
    // 以及一个 nwsocket 用来发送数据
    public var socket: NWUDPSocket?
    public var agent: SOCKS5AssociateAdapter?

    public override init() {}
}

/// This stack tranmits UDP packets directly.
public class UDPAssociateStack: IPStackProtocol, NWUDPSocketDelegate {
    let socks5Host: String
    let socks5Port: Int
    let socks5AuthUsername: String?
    let socks5AuthPassword: String?
    fileprivate var activeSessions: [ConnectInfo: UDPAssociateSession] = [:]
    public var outputFunc: (([Data], [NSNumber]) -> Void)!

    fileprivate let queue: DispatchQueue = DispatchQueue(label: "NEKit.UDPAssociateStack.SocketArrayQueue", attributes: [])
    
    public init(_ auth: socks5Auth) {
        socks5Host = auth.host
        socks5Port = auth.port
        socks5AuthUsername = auth.username
        socks5AuthPassword = auth.password
    }

    /**
     Input a packet into the stack.

     - note: Only process IPv4 UDP packet as of now.

     - parameter packet:  The IP packet.
     - parameter version: The version of the IP packet, i.e., AF_INET, AF_INET6.

     - returns: If the stack accepts in this packet. If the packet is accepted, then it won't be processed by other IP stacks.
     */
    public func input(packet: Data, version: NSNumber?) -> Bool {
        if let version = version {
            // we do not process IPv6 packets now
            if version.int32Value == AF_INET6 {
                return false
            }
        }
        if IPPacket.peekDestinationPort(packet) == 53 {
            DDLogInfo("拿到了dns请求:\(IPPacket.peekDestinationAddress(packet)!)")
//            return false
        }
        if IPPacket.peekProtocol(packet) == .udp {
            input(packet)
            return true
        }
        return false
    }

    public func start() {

    }

    public func stop() {
        queue.async {
            for session in self.activeSessions.values {
                session.socket?.disconnect()
                session.agent?.socket.disconnect()
            }
            self.activeSessions = [:]
        }
    }

    fileprivate func input(_ packetData: Data) {
        guard let packet = IPPacket(packetData: packetData) else {
            return
        }

        guard let (info, session) = findOrCreateSessionForPacket(packet) else {
            return
        }

        if session.agent?.host == nil || session.agent?.port == nil {
            // 将来考虑增加一个 buffer，然后在 delegate 里做重试
            return
        }

        if session.socket == nil {
            guard let udpSocket = NWUDPSocket(host: session.agent!.host!, port: session.agent!.port!) else {
                return
            }
            udpSocket.delegate = self
            queue.sync {
                self.activeSessions[info]!.socket = udpSocket
            }
            session.socket = udpSocket
        }

        // swiftlint:disable:next force_cast
        let payload = (packet.protocolParser as! UDPProtocolParser).payload
        let port = info.destinationPort.value
        let p1 = UInt8(port >> 8)
        let p2 = UInt8(port & 0xff)
        let socks5payload = [0x0, 0x0, 0x0, 0x1] + [UInt8](packet.destinationAddress.dataInNetworkOrder) + [p1, p2]
        session.socket!.write(data: Data(socks5payload) + payload!)
    }

    fileprivate func findSession(connectInfo: ConnectInfo?, socket: NWUDPSocket?) -> (ConnectInfo, UDPAssociateSession)? {
        var result: (ConnectInfo, UDPAssociateSession)?

        queue.sync {
            if connectInfo != nil {
                guard let session = self.activeSessions[connectInfo!] else {
                    result = nil // 这里返回之后，就是创建流程
                    return
                }
                result = (connectInfo!, session)
                return
            }

            // 当从 relay server 返回数据的时候需要能从 socket 找回 connectInfo, 才能发回给应用
            guard let socket = socket else {
                result = nil
                return
            }

            guard let index = self.activeSessions.firstIndex(where: { _, session in
                return socket === session.socket
            }) else {
                result = nil
                return
            }

            result = self.activeSessions[index]
        }
        return result
    }

    fileprivate func findOrCreateSessionForPacket(_ packet: IPPacket) -> (ConnectInfo, UDPAssociateSession)? {
        // swiftlint:disable:next force_cast
        let udpParser = packet.protocolParser as! UDPProtocolParser
        let connectInfo = ConnectInfo(sourceAddress: packet.sourceAddress, sourcePort: udpParser.sourcePort, destinationAddress: packet.destinationAddress, destinationPort: udpParser.destinationPort)

        if let (_, session) = findSession(connectInfo: connectInfo, socket: nil) {
            return (connectInfo, session)
        }

        let session = UDPAssociateSession()
        session.agent = SOCKS5AssociateAdapter(serverHost: socks5Host, serverPort: socks5Port,
                                               username: socks5AuthUsername, password: socks5AuthPassword)
        session.agent?.socket = RawSocketFactory.getRawSocket()
        session.agent?.delegate = session
        session.agent?.openSocketWith(session: ConnectSession(host: "0.0.0.0", port: 0, fakeIPEnabled: false)!)

        queue.sync {
            self.activeSessions[connectInfo] = session
        }
        return (connectInfo, session)
    }

    public func didReceive(data: Data, from: NWUDPSocket) {
        guard let (connectInfo, _) = findSession(connectInfo: nil, socket: from) else {
            return
        }
        guard data.count > 10 else {
            return
        }
        let ip = "\(data[4]).\(data[5]).\(data[6]).\(data[7])"
        let port = Int(data[8])*256+Int(data[9])
        DDLogVerbose("didReceive: \(ip) vs \(connectInfo.destinationAddress); \(port) vs \(connectInfo.destinationPort)")

        let payload = data.subdata(in: 10..<data.count)

        let packet = IPPacket()
        packet.sourceAddress = connectInfo.destinationAddress
        packet.destinationAddress = connectInfo.sourceAddress
        let udpParser = UDPProtocolParser()
        udpParser.sourcePort = connectInfo.destinationPort
        udpParser.destinationPort = connectInfo.sourcePort
        udpParser.payload = payload
        packet.protocolParser = udpParser
        packet.transportProtocol = .udp
        packet.buildPacket()

        outputFunc([packet.packetData], [NSNumber(value: AF_INET as Int32)])
    }

    public func didCancel(socket: NWUDPSocket) {
        guard let (info, _) = findSession(connectInfo: nil, socket: socket) else {
            return
        }

        activeSessions.removeValue(forKey: info)
    }
}
