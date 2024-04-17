//
//  SharedData.swift
//  NiiVue
//
//  Created by Taylor Hanayik on 17/04/2024.
//

import Foundation
import Combine

class SharedData: ObservableObject {
    @Published var location: String = ""
}
