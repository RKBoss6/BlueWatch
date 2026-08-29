//
//  LocalData.swift
//  BlueWatch
//
//  Created by Kabir Onkar on 3/25/26.
//

import Foundation
import SwiftUI
import Combine


class LocalData:ObservableObject {
    static let shared=LocalData();
    @Published public var battery:String="--"
}
