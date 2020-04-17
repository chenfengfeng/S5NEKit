//
//  ViewController.swift
//  demo
//
//  Created by Feng on 2020/4/17.
//  Copyright © 2020 Zhuhao Wang. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var switchBtn: UISwitch!
    
    var status: VPNStatus {
        didSet(o) {
            updateConnectButton()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.status = .off
        super.init(coder: aDecoder)
        NotificationCenter.default.addObserver(self, selector: #selector(onVPNStatusChanged), name: kProxyServiceVPNStatusNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: kProxyServiceVPNStatusNotification, object: nil)
    }
    
    @objc func onVPNStatusChanged(){
        self.status = VpnManager.shared.vpnStatus
    }
    
    func updateConnectButton(){
        switch status {
        case .connecting:
            break
        case .disconnecting:
            break
        case .on:
            switchBtn.isOn = true
            break
        case .off:
            switchBtn.isOn = false
            break
        }
    }

    @IBAction func clickSwitch(_ sender: UISwitch) {
        if sender.isOn {
            VpnManager.shared.host = "202.60.250.190"
            VpnManager.shared.port = 9286
            VpnManager.shared.name = "900182:MT163AAFE857FC76B4F678B6CA95B69E611E7"
            VpnManager.shared.dns  = "114.114.114.114"
            VpnManager.shared.password = "4BPiTF0isY33MVJe"
            VpnManager.shared.endtime  = 1687090004
            VpnManager.shared.connect()
        }else{
            VpnManager.shared.disconnect()
        }
    }
    
}

