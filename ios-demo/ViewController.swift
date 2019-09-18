//
//  ViewController.swift
//  ios-demo
//
//  Created by Feng on 2019/9/17.
//  Copyright © 2019 Zhuhao Wang. All rights reserved.
//

import UIKit
import NEKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let socksAdapterFactory = SOCKS5AdapterFactory(serverHost: "127.0.0.1", serverPort: 1086)
        // 规则
        var UserRules:[NEKit.Rule] = []
        let allRule = AllRule(adapterFactory: socksAdapterFactory)
        UserRules.append(contentsOf: [allRule])
        
        let manager = RuleManager(fromRules: UserRules, appendDirect: true)
        
        RuleManager.currentManager = manager
    }


}

