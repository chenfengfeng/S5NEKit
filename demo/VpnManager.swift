let kProxyServiceVPNStatusNotification = Notification.Name(rawValue:"kProxyServiceVPNStatusNotification")

import Foundation
import NetworkExtension

enum VPNStatus {
    case off
    case connecting
    case on
    case disconnecting
}

class VpnManager{
    
    public var host: String = ""
    public var port: Int = 0
    public var name: String = ""
    public var password: String = ""
    public var dns: String = ""
    public var endtime: TimeInterval = 0
    
    static let shared = VpnManager()
    var observerAdded: Bool = false
    
    fileprivate(set) var vpnStatus = VPNStatus.off {
        didSet {
            NotificationCenter.default.post(name: kProxyServiceVPNStatusNotification, object: nil)
        }
    }
    
    init() {
        loadProviderManager{
            guard let manager = $0 else{return}
            self.updateVPNStatus(manager)
        }
        addVPNStatusObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func addVPNStatusObserver() {
        guard !observerAdded else{
            return
        }
        loadProviderManager { [unowned self] (manager) -> Void in
            if let manager = manager {
                self.observerAdded = true
                NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: manager.connection, queue: OperationQueue.main, using: { [unowned self] (notification) -> Void in
                    self.updateVPNStatus(manager)
                })
            }
        }
    }
    
    func updateVPNStatus(_ manager: NEVPNManager) {
        switch manager.connection.status {
        case .connected:
            self.vpnStatus = .on
        case .connecting, .reasserting:
            self.vpnStatus = .connecting
        case .disconnecting:
            self.vpnStatus = .disconnecting
        case .disconnected, .invalid:
            self.vpnStatus = .off
        @unknown default: break
            
        }
        print(self.vpnStatus)
    }
}

// load VPN Profiles
extension VpnManager{

    fileprivate func createProviderManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let conf = NETunnelProviderProtocol()
        conf.serverAddress = "127.0.0.1"
        manager.protocolConfiguration = conf
        manager.localizedDescription = "demo"
        return manager
    }
    
    func loadAndCreatePrividerManager(_ complete: @escaping (NETunnelProviderManager?) -> Void ){
        NETunnelProviderManager.loadAllFromPreferences{ (managers, error) in
            guard let managers = managers else{return}
            let manager: NETunnelProviderManager
            if managers.count > 0 {
                manager = managers[0]
                self.delDupConfig(managers)
            }else{
                manager = self.createProviderManager()
            }
            
            manager.isEnabled = true
            self.setRulerConfig(manager)
            manager.saveToPreferences{
                if ($0 != nil){
                }
                manager.loadFromPreferences{
                    if $0 != nil{
                        print($0.debugDescription)
                        complete(nil);return;
                    }
                    self.addVPNStatusObserver()
                    complete(manager)
                }
            }
            
        }
    }
    
    func loadProviderManager(_ complete: @escaping (NETunnelProviderManager?) -> Void){
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let managers = managers {
                if managers.count > 0 {
                    let manager = managers[0]
                    complete(manager)
                    return
                }
            }
            complete(nil)
        }
    }
    
    
    func delDupConfig(_ arrays:[NETunnelProviderManager]){
        if (arrays.count)>1{
            for i in 0 ..< arrays.count{
                arrays[i].removeFromPreferences(completionHandler: { (error) in
                    if(error != nil){print(error.debugDescription)}
                })
            }
        }
    }
}

// Actions
extension VpnManager{
    func connect(){
        self.loadAndCreatePrividerManager { (manager) in
            guard let manager = manager else{return}
            do{
                try manager.connection.startVPNTunnel(options: [:])
            }catch let err{
                self.vpnStatus = .off
                print(err)
            }
        }
    }
    
    func disconnect(){
        loadProviderManager{
            $0?.connection.stopVPNTunnel()
        }
    }
}

// Generate and Load ConfigFile
extension VpnManager{
    
    fileprivate func setRulerConfig(_ manager:NETunnelProviderManager){
        
        var conf = [String:AnyObject]()
        conf["ss_host"] = host as AnyObject?
        conf["ss_port"] = port as AnyObject?
        conf["ss_name"] = name as AnyObject?
        conf["ss_dns"]  = dns  as AnyObject?
        conf["ss_time"] = endtime as AnyObject?
        conf["ss_pwd"]  = password as AnyObject?
        let orignConf = manager.protocolConfiguration as! NETunnelProviderProtocol
        orignConf.providerConfiguration = conf
        manager.protocolConfiguration = orignConf
    }
}
