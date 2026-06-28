//
//  String+NilIfEmpty.swift
//

import Foundation

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
