NEKit
通过https://gitter.im/zhuhaow/NEKit加入聊天 通过https://telegram.me/NEKitGroup加入聊天 建立状态 GitHub版本 代码气候 编码 迦太基兼容 GitHub许可证

网络扩展框架的工具包。

NEKit是Soca的继任者。NEKit的主要目标是在构建Network Extension应用程序时提供所需的功能，NETunnelProvider以绕过网络过滤和审查，同时保持框架尽可能不受干扰。

NEKit不依赖于网络扩展框架。您可以使用没有网络扩展权限的NEKit在几行中构建基于规则的代理。

TUNInterface由于它无法正常工作，请暂时不要启用它。

您应该签出两个演示。

SpechtLite不需要网络扩展，任何人都可以使用它。

Specht是另一个需要网络扩展授权的演示。

目前，NEKit支持：

根据远程主机位置，远程主机域或代理的连接速度，通过不同的代理转发请求。
集成的tun2socks框架可将TCP数据包重组为TCP流。
重写请求和响应的DNS服务器。
一些用于构建IP数据包的工具。
…
在这里检查文件。

另外，如果您只需要带有GUI支持shadowsocks的开源iOS应用，您可能会对Potatso更加感兴趣。

Wingy是使用NEKit构建的免费应用程序，可在App Store上为您的iDevice使用。注意Wingy不是由我创建或与我无关。

如果您有任何疑问（不是错误报告），请加入Gitter或Telegram，而不要提出问题。

原理
NEKit试图变得尽可能灵活和不受限制。

但是，如果您想从网络层重现传输层，它并不一定像您想的那样模块化。

NEKit遵循一项基本原则以保持最佳的网络性能：连接到目标服务器的设备直接解析域。

如果您设备上的应用程序直接连接到本地代理服务器，那么这应该不是问题，在这里我们可以获取请求域信息，然后根据需要将其发送到远程代理服务器。

但是请考虑一下，如果应用程序试图自己建立套接字连接，通常包括两个步骤：

进行DNS查找以找到目标服务器的IP地址。
通过系统提供的套接字API连接到远程服务器。
我们只能从TUN接口读取两个独立的信息，一个是包含DNS查找请求的UDP数据包，另一个是由一系列TCP数据包组成的TCP流。因此，我们无法知道TCP流的初始请求域。而且由于同一主机上可能有多个域，因此无法通过保存DNS响应并稍后反向查找来获得源域。

唯一的解决方案是创建一个伪IP池，并为每个请求的域分配一个唯一的伪IP，这样我们就可以反向查找。之后，每个连接都需要从DNS服务器进行查找；这是NEKit唯一已封装在中的非模块化部分ConnectSession。

用法
将其添加到您的项目
我建议将此项目添加到您的项目中，这样更易​​于调试。

但是，您仍然可以将其与Carthage一起使用（由于NEKit使用Carthage，因此您仍然需要Carthage），方法是添加

github "zhuhaow/NEKit"
给你Cartfile。

使用 carthage update --no-use-binaries --platform mac,ios 安装所有的框架。不要使用预编译的二进制文件，因为其中一些可能是错误的。

总览
NEKit基本上由两部分组成：代理服务器根据用户定义的规则转发套接字数据； IP堆栈将IP数据包作为套接字重新组合到TCP流中。

规则管理员
在启动任何代理服务器之前，我们需要定义规则。

每个规则由两部分组成，一个部分定义与该规则匹配的请求种类，另一部分定义要使用的适配器。适配器表示与远程代理服务器（或远程主机）的套接字连接的抽象。我们AdapterFactory用来构建适配器。

NEKit提供了AdapterSocket支持的HTTP / HTTPS / SOCK5代理和Shadowsocks（AES-128-CFB / AES-192-CFB / AES-256-CFB / chacha20 / salsa20 / rc4-md5）。让我知道是否需要其他任何类型的代理。您也可以实现自己的AdapterSocket。

// Define remote adapter first
let directAdapterFactory = DirectAdapterFactory()
let httpAdapterFactory = HTTPAdapterFactory(serverHost: "remote.http.proxy", serverPort: 3128, auth: nil)
let ssAdapterFactory = ShadowsocksAdapterFactory(serverHost: "remote.ss.proxy", serverPort: 7077, encryptMethod: "AES-256-CFB", password: "1234567890")

// Then create rules
let chinaRule = CountryRule(countryCode: "CN", match: true, adapterFactory: directAdapterFactory)
// `urls` are regular expressions
let listRule = try! ListRule(adapterFactory: ssAdapterFactory, urls: ["some\\.site\\.does\\.not\\.exists"])
let allRule = AllRule(adapterFactory: httpAdapterFactory)

// Create rule manager, rules will be matched in order.
let manager = RuleManager(fromRules: [listRule, chinaRule, allRule], appendDirect: true)

// Set this manager as the active manager
RuleManager.currentManager = ruleManager
还Configuration可以从Yaml配置文件中加载规则。但是不建议这样做。

代理服务器
现在，我们可以在本地启动HTTP / SOCKS5代理服务器。

let server = GCDHTTPProxyServer(address: IPv4Address(fromString: "127.0.0.1"), port: Port(port: 9090)
try! server.start()
现在有一个HTTP代理服务器正在运行，127.0.0.1:9090该服务器将根据中定义的规则转发请求RuleManager.currentManager。

如果您不想处理IP数据包，仅此而已，只需127.0.0.1:9090在“系统偏好设置”中将代理设置为即可。

如果您想继续阅读，则必须向Apple请求网络扩展权利。

但是，即使您使用NetworkExtention设置网络代理，也并不意味着您必须处理数据包，只是不要将任何内容路由到TUN接口，也不要进行设置IPStack。对于iOS，如果您声称已实现，但什么也不做，用户可能永远不会注意到。

IP堆栈
假设您已经使用正确的路由配置设置了一个有效的扩展程序（谷歌如何，这并不容易）。

在

startTunnelWithOptions(options: [String : NSObject]?, completionHandler: (NSError?) -> Void)
设置RuleManager并启动代理服务器，然后通过以下方式创建代表TUN接口的实例

let stack = TUNInterface(packetFlow: packetFlow)
我们还必须设置

RawSocketFactory.TunnelProvider = self
创建套接字以使用来连接到远程服务器NETunnelProvider。

然后，我们需要注册IPStackProtocol用于处理IP数据包的ip堆栈。

NEKit提供了几个堆栈。

TCP协议栈
TCPStack处理TCP数据包并将其重新组合回TCP流，然后将其发送到proxyServer变量指定的代理服务器。你必须设置proxyServer在注册前TCPStack到TUNInterface。

DNS服务器
DNS服务器被实现为处理UDP数据包的IP堆栈。

首先创建一个带有假IP池的DNS服务器。（您应该使用伪造的IP，但是如果要禁用它，可以将其设置为nil。）

let fakeIPPool = IPv4Pool(start: IPv4Address(fromString: "172.169.1.0"), end: IPv4Address(fromString: "172.169.255.0"))
let dnsServer = DNSServer(address: IPv4Address(fromString: "172.169.0.1"), port: Port(port: 53), fakeIPPool: fakeIPPool)
然后，我们必须定义如何解析DNS请求，NEKit提供了最简单的方法，它使用UDP协议将请求直接发送到远程DNS服务器，您可以通过实现来做任何您想做的事情DNSResolverProtocol。

let resolver = UDPDNSResolver(address: IPv4Address(fromString: "114.114.114.114"), port: Port(port: 53))
dnsServer.registerResolver(resolver)
设置非常重要

DNSServer.currentServer = dnsServer
因此我们可以反向查找虚假IP。

UDP直接堆叠
UDPDirectStack 直接在远程服务器之间发送和读取UDP数据包。

您可以通过以下方式将这些堆栈注册到TUN接口

interface.registerStack(dnsServer)
// Note this sends out every UDP packets directly so this must comes after any other stack that processes UDP packets.
interface.registerStack(UDPDirectStack())
interface.registerStack(TCPStack.stack)
一切设置完成后，您应该通过调用interface.start()的完成处理程序来开始处理数据包setTunnelNetworkSettings。

事件
您可以Observer<T>用来观察代理服务器和套接字中的事件。以观察者DebugObserver.swift为例。

潜入
框架概述
代理服务器的结构如下：

┌──────────────────────────────────────────────────┐
│                                                  │
│                   ProxyServer                    │
│                                                  │
├──────┬───┬──────┬───┬──────┬───┬──────┬───┬──────┤
│Tunnel│   │Tunnel│   │Tunnel│   │Tunnel│   │Tunnel│
└──────┘   └──────┘   └───▲──┘   └──────┘   └──────┘
                         ╱ ╲                        
                ╱───────╱   ╲─────╲                 
               ╱                   ╲                
     ┌────────▼────────┐   ┌────────▼────────┐      
     │   ProxySocket   │   │  AdapterSocket  │      
     └────────▲────────┘   └────────▲────────┘      
              │                     │               
              │                     │               
     ┌────────▼────────┐   ┌────────▼────────┐      
     │RawSocketProtocol│   │RawSocketProtocol│      
     └────────▲────────┘   └────────▲────────┘      
              │                     │               
              │                     │               
       ╔══════▼═══════╗     ╔═══════▼══════╗        
       ║    LOCAL     ║     ║    REMOTE    ║        
       ╚══════════════╝     ╚══════════════╝        
当从代理服务器的侦听套接字接受新套接字时，它将以某种RawSocketProtocol原始包装形式封装在原始实现中，该套接字仅用于读取和写入数据。

然后将其包装在一个子类中，ProxySocket该子类封装了代理逻辑。

该TCPStack包裹重新组装的TCP流量（TUNTCPSocket）中DirectProxySocket，然后将其发送到mainProxy服务器。

同样，AdapterSocket封装了如何连接到远程并处理数据流的逻辑。

NEKit几乎所有内容都遵循委托模式。如果您不熟悉它，则应该首先学习它，方法可能是学习如何使用CocoaAsyncSocket（请注意，NEKit中的套接字不是线程安全的，这与GCDAsyncSocket不同）。

一生 Tunnel
当RawSocketProtocol套接字接受或创建时TCPStack，它将包裹在a中，ProxySocket然后包裹在Tunnel。该Tunnel会打电话proxySocket.openSocket()让代理插座开始处理数据。

当ProxySocket读取足够的数据来建立一个ConnectSession，它调用func didReceiveRequest(request: ConnectSession, from: ProxySocket)了的delegate（应该是Tunnel）。

在Tunnel那么这个请求相匹配RuleManager，以获得相应的AdapterFactory。然后func openSocketWithSession(session: ConnectSession)产生的AdapterSocket被调用以连接到远程服务器。

该AdapterSocket电话func didConnect(adapterSocket: AdapterSocket, withResponse response: ConnectResponse)的Tunnel，让ProxySocket有机会到远程响应响应。（到目前为止，这已被忽略。）

最后，当ProxySocket并AdapterSocket准备转发数据，他们应该打电话func readyToForward(socket: SocketProtocol)的Tunnel，让它知道。当双方准备就绪时，隧道将从双方进行读取，然后将接收到的数据原封不动地发送到另一侧。

当隧道的任一侧断开连接时，将func didDisconnect(socket: SocketProtocol)调用，然后主动关闭两侧。Tunnel当双方成功断开连接时，将释放。

去做
[]文件。
[] IPv6支持。
执照
版权所有©2016，Zhuhao Wang版权所有。

如果满足以下条件，则允许以源代码和二进制形式进行重新分发和使用，无论是否经过修改，都可以：

重新分发源代码必须保留以上版权声明，此条件列表和以下免责声明。

二进制形式的重新分发必须在分发随附的文档和/或其他材料中复制以上版权声明，此条件列表以及以下免责声明。

未经事先特别书面许可，不得使用NEKit的名称或其贡献者的名称来认可或促销从该软件衍生的产品。

本软件由版权所有者和贡献者AS IS任何明示或默示的担保，包括但不限于针对特定用途的适销性和适用性的暗示担保。在任何情况下，版权持有人或贡献者均不对任何直接，间接，偶发，特殊，专有或后果性的损害（包括但不限于，替代商品或服务的购买，使用，数据，或业务中断），无论基于合同，严格责任或侵权行为（包括疏忽或其他方式），无论是出于任何责任，无论是否出于使用本软件的目的，即使已经事先告知，也已作了规定。
