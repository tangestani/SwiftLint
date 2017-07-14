//
//  Configuration+Nesting.swift
//  SwiftLint
//
//  Created by JP Simard on 7/13/17.
//  Copyright © 2017 Realm. All rights reserved.
//

import Foundation

extension Configuration {
    internal func configuration(forPath path: String) -> Configuration {
        if path == rootPath {
            return self
        }

        let pathNSString = path.bridge()
        let configurationSearchPath = pathNSString.appendingPathComponent(Configuration.fileName)

        // If a configuration exists and it isn't us, load and merge the configurations
        if configurationSearchPath != configurationPath &&
            FileManager.default.fileExists(atPath: configurationSearchPath) {
            let fullPath = pathNSString.absolutePathRepresentation()
            let config = Configuration.getCached(atPath: fullPath) ??
                Configuration(path: configurationSearchPath, rootPath: rootPath, optional: false, quiet: true)
            return merge(with: config)
        }

        // If we are not at the root path, continue down the tree
        if path != rootPath && path != "/" {
            return configuration(forPath: pathNSString.deletingLastPathComponent)
        }

        // If nothing else, return self
        return self
    }

    internal struct HashableRule: Hashable {
        let rule: Rule

        static func == (lhs: HashableRule, rhs: HashableRule) -> Bool {
            // Don't use `isEqualTo` in case its internal implementation changes from
            // using the identifier to something else, which could mess up with the `Set`
            return type(of: lhs.rule).description.identifier == type(of: rhs.rule).description.identifier
        }

        var hashValue: Int {
            return type(of: rule).description.identifier.hashValue
        }
    }
//
//    internal func merge(with configuration: Configuration) -> Configuration {
//        var rules: [Rule] = []
//        if !configuration.whitelistRules.isEmpty {
//            // Use an intermediate set to filter out duplicate rules when merging configurations
//            // (always use the nested rule first if it exists)
//            var ruleSet = Set<HashableRule>(configuration.rules.map { HashableRule(rule: $0) })
//            ruleSet.formUnion(self.rules.map { HashableRule(rule: $0) })
//            rules = ruleSet.map { $0.rule }.filter { rule in
//                return configuration.whitelistRules.contains(type(of: rule).description.identifier)
//            }
//        } else {
//            // Same here
//            var ruleSet = Set<HashableRule>(configuration.rules
//                // Enable rules that are opt-in by the nested configuration
//                .filter { rule in
//                    return configuration.optInRules.contains(type(of: rule).description.identifier)
//                }
//                .map { HashableRule(rule: $0) })
//            // And disable rules that are disabled by the nested configuration
//            ruleSet.formUnion(self.rules
//                .filter { rule in
//                    return !configuration.disabledRules.contains(type(of: rule).description.identifier)
//                }.map { HashableRule(rule: $0) })
//            rules = ruleSet.map { $0.rule }
//        }
//        var nestedConfiguration = Configuration(
//            disabledRules: [],
//            optInRules: [],
//            included: configuration.included, // Always use the nested included directories
//            excluded: configuration.excluded, // Always use the nested excluded directories
//            // The minimum warning threshold if both exist, otherwise the nested,
//            // and if it doesn't exist try to use the parent one
//            warningThreshold: self.warningThreshold.map { warningThreshold in
//                return configuration.warningThreshold.map {
//                    min($0, warningThreshold)
//                    } ?? warningThreshold
//                } ?? configuration.warningThreshold,
//            reporter: self.reporter, // Always use the parent reporter
//            rules: rules,
//            cachePath: self.cachePath) // Always use the parent cache path
//        nestedConfiguration.rootPath = configuration.rootPath
//        return nestedConfiguration
//    }
}
