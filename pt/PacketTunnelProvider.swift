//
//  PacketTunnelProvider.swift
//  pt
//
//  Created by Feng on 2020/4/17.
//  Copyright © 2020 Zhuhao Wang. All rights reserved.
//

import CocoaLumberjackSwift
import NetworkExtension
import NEKit
import MMDB

class LogFormatter: NSObject, DDLogFormatter {
    func format(message logMessage: DDLogMessage) -> String? {
        return "VPNLOG: \(logMessage.message)"
    }
}

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    var enablePacketProcessing = true
    var httpProxy: GCDProxyServer!
    var interface: TUNInterface!
    var started: Bool = false
    var auth = socks5Auth()
    var lastPath: NWPath?
    var ss_dns: String!
    
    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        
        DDLogInfo("准备连接VPN")
        
        guard let conf = (protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration else{
            DDLogInfo("[错误]找不到协议配置")
            exit(EXIT_FAILURE)
        }
        
        auth.host = conf["ss_host"] as? String
        auth.port = conf["ss_port"] as? Int
        auth.username = conf["ss_name"] as? String
        auth.password  = conf["ss_pwd"]  as? String
        auth.endtime   = conf["ss_time"] as? TimeInterval
        
        ss_dns  = conf["ss_dns"]  as? String
        
        let s5AdapterFactory = SOCKS5AuthAdapterFactory(auth)
        
        var UserRules:[NEKit.Rule] = []
        
        let allRule = AllRule(adapterFactory: s5AdapterFactory)
        UserRules.append(contentsOf: [allRule])
        let manager = RuleManager(fromRules: UserRules, appendDirect: true)
        
        RuleManager.currentManager = manager
        RawSocketFactory.TunnelProvider = self
        let path = Bundle.main.path(forResource: "GeoLite2-Country", ofType: "mmdb")!
        GeoIP.database = MMDB(path)!
        
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        
        let ipv4Settings = NEIPv4Settings(addresses: ["10.0.0.2"], subnetMasks: ["255.255.255.0"])
        ipv4Settings.includedRoutes = [NEIPv4Route.default()]
        ipv4Settings.excludedRoutes = [
            NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
            NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
            NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
            NEIPv4Route(destinationAddress: ss_dns, subnetMask: "255.255.255.255")
        ]
        networkSettings.ipv4Settings = ipv4Settings
        
        let DNSSettings = NEDNSSettings(servers: [ss_dns])
        DNSSettings.matchDomains = [""]
        networkSettings.dnsSettings = DNSSettings
        
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: 6152)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: 6152)
        proxySettings.excludeSimpleHostnames = false
        proxySettings.matchDomains = [""]
        networkSettings.proxySettings = proxySettings
        
        setTunnelNetworkSettings(networkSettings) { error in
            guard error == nil else {
                completionHandler(error)
                return
            }
            
            if !self.started {
                // 下面的观察者要检查网络变化并重启服务
                self.addObserver(self, forKeyPath: "defaultPath", options: .initial, context: nil)
                if #available(iOSApplicationExtension 10.0, *) {
                    DDLog.add(DDOSLogger.sharedInstance, with: DDLogLevel.verbose)
                    DDOSLogger.sharedInstance.logFormatter = LogFormatter()
                }
                Opt.MAXNWTCPSocketReadDataSize = 64 * 1024 - 1
            }
            
            if !self.started {
                self.httpProxy = GCDHTTPProxyServer(address: IPAddress(fromString: "127.0.0.1"), port: 6152)
                try! self.httpProxy.start()
            }
            
            completionHandler(nil)
            
            if self.enablePacketProcessing {
                if !self.started {
                    self.interface = TUNInterface(packetFlow: self.packetFlow)

                    let udpStack = UDPAssociateStack(self.auth)
                    self.interface.register(stack: udpStack)

                    let tcpStack = TCPStack.stack
                    tcpStack.proxyServer = self.httpProxy
                    self.interface.register(stack:tcpStack)

                    self.interface.start()
                }
            }
            self.started = true
        }
    }
    
    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        stopVPNServer()
        completionHandler()
        exit(EXIT_SUCCESS)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "defaultPath" {
            if self.defaultPath?.status == .satisfied && interface != nil{
                if(lastPath == nil){
                    lastPath = self.defaultPath
                }
                stopVPNServer()
                DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                    DDLogInfo("重启VPN服务")
                    self.startTunnel(options: nil){_ in}
                }
            }else{
                lastPath = defaultPath
            }
        }
    }
    
    private func stopVPNServer() {
        if enablePacketProcessing {
            interface.stop()
            interface = nil
        }
        if(httpProxy != nil){
            httpProxy.stop()
            httpProxy = nil
            started = false
            RawSocketFactory.TunnelProvider = nil
        }
        self.removeObserver(self, forKeyPath: "defaultPath")
    }
}
