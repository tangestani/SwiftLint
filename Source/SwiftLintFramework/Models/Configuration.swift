//
//  Configuration.swift
//  SwiftLint
//
//  Created by JP Simard on 8/23/15.
//  Copyright © 2015 Realm. All rights reserved.
//

import Foundation
import SourceKittenFramework

// swiftlint:disable file_length
// The nested configuration part could probably be split up in another file
public struct Configuration: Equatable {
    public static let fileName = ".swiftlint.yml"
    public let included: [String]             // included
    public let excluded: [String]             // excluded
    public let reporter: String               // reporter (xcode, json, csv, checkstyle)
    public var warningThreshold: Int?         // warning threshold
    internal let disabledRules: [String]
    internal let optInRules: [String]
    internal let whitelistRules: [String]
    public let rules: [Rule]
    public var rootPath: String?              // the root path to search for nested configurations
    public var configurationPath: String?     // if successfully loaded from a path
    public let cachePath: String?

    public init?(disabledRules: [String] = [],
                 optInRules: [String] = [],
                 enableAllRules: Bool = false,
                 whitelistRules: [String] = [],
                 included: [String] = [],
                 excluded: [String] = [],
                 warningThreshold: Int? = nil,
                 reporter: String = XcodeReporter.identifier,
                 ruleList: RuleList = masterRuleList,
                 configuredRules: [Rule]? = nil,
                 swiftlintVersion: String? = nil,
                 cachePath: String? = nil) {

        if let pinnedVersion = swiftlintVersion, pinnedVersion != Version.current.value {
            queuedPrintError("Currently running SwiftLint \(Version.current.value) but " +
                "configuration specified version \(pinnedVersion).")
        }

        let configuredRules = configuredRules
            ?? (try? ruleList.configuredRules(with: [:]))
            ?? []

        let handleAliasWithRuleList = { (alias: String) -> String in
            return ruleList.identifier(for: alias) ?? alias
        }

        let disabledRules = disabledRules.map(handleAliasWithRuleList)
        let optInRules = optInRules.map(handleAliasWithRuleList)
        let whitelistRules = whitelistRules.map(handleAliasWithRuleList)

        // Validate that all rule identifiers map to a defined rule
        let validRuleIdentifiers = validateRuleIdentifiers(configuredRules: configuredRules,
                                                           disabledRules: disabledRules)
        let validDisabledRules = disabledRules.filter(validRuleIdentifiers.contains)

        // Validate that rule identifiers aren't listed multiple times
        if containsDuplicateIdentifiers(validDisabledRules) {
            return nil
        }

        // Precedence is enableAllRules > whitelistRules > everything else
        let rules: [Rule]
        if enableAllRules {
            rules = configuredRules
        } else if !whitelistRules.isEmpty {
            if !disabledRules.isEmpty || !optInRules.isEmpty {
                queuedPrintError("'\(Key.disabledRules.rawValue)' or " +
                    "'\(Key.optInRules.rawValue)' cannot be used in combination " +
                    "with '\(Key.whitelistRules.rawValue)'")
                return nil
            }

            rules = configuredRules.filter { rule in
                return whitelistRules.contains(type(of: rule).description.identifier)
            }
        } else {
            rules = configuredRules.filter { rule in
                let id = type(of: rule).description.identifier
                if validDisabledRules.contains(id) { return false }
                return optInRules.contains(id) || !(rule is OptInRule)
            }
        }
        self.init(disabledRules: disabledRules,
                  optInRules: optInRules,
                  whitelistRules: whitelistRules,
                  included: included,
                  excluded: excluded,
                  warningThreshold: warningThreshold,
                  reporter: reporter,
                  rules: rules,
                  cachePath: cachePath)
    }

    internal init(disabledRules: [String] = [],
                  optInRules: [String] = [],
                  whitelistRules: [String] = [],
                  included: [String] = [],
                  excluded: [String] = [],
                  warningThreshold: Int? = nil,
                  reporter: String,
                  rules: [Rule] = [],
                  cachePath: String? = nil) {

        self.disabledRules = disabledRules
        self.optInRules = optInRules
        self.whitelistRules = whitelistRules
        self.included = included
        self.excluded = excluded
        self.reporter = reporter
        self.cachePath = cachePath
        self.rules = rules

        // set the config threshold to the threshold provided in the config file
        self.warningThreshold = warningThreshold
    }

    public init?(dict: [String: Any], ruleList: RuleList = masterRuleList, enableAllRules: Bool = false,
                 cachePath: String? = nil) {
        func defaultStringArray(_ object: Any?) -> [String] {
            return [String].array(of: object) ?? []
        }

        // Use either new 'opt_in_rules' or deprecated 'enabled_rules' for now.
        let optInRules = defaultStringArray(
            dict[Key.optInRules.rawValue] ?? dict[Key.enabledRules.rawValue]
        )

        // Log an error when supplying invalid keys in the configuration dictionary
        let invalidKeys = Set(dict.keys).subtracting(Configuration.validKeys(ruleList: ruleList))
        if !invalidKeys.isEmpty {
            queuedPrintError("Configuration contains invalid keys:\n\(invalidKeys)")
        }

        let disabledRules = defaultStringArray(dict[Key.disabledRules.rawValue])
        let whitelistRules = defaultStringArray(dict[Key.whitelistRules.rawValue])
        let included = defaultStringArray(dict[Key.included.rawValue])
        let excluded = defaultStringArray(dict[Key.excluded.rawValue])

        warnAboutDeprecations(configurationDictionary: dict, disabledRules: disabledRules, optInRules: optInRules,
                              whitelistRules: whitelistRules, ruleList: ruleList)

        let configuredRules: [Rule]
        do {
            configuredRules = try ruleList.configuredRules(with: dict)
        } catch RuleListError.duplicatedConfigurations(let ruleType) {
            let aliases = ruleType.description.deprecatedAliases.map { "'\($0)'" }.joined(separator: ", ")
            let identifier = ruleType.description.identifier
            queuedPrintError("Multiple configurations found for '\(identifier)'. Check for any aliases: \(aliases).")
            return nil
        } catch {
            return nil
        }

        self.init(disabledRules: disabledRules,
                  optInRules: optInRules,
                  enableAllRules: enableAllRules,
                  whitelistRules: whitelistRules,
                  included: included,
                  excluded: excluded,
                  warningThreshold: dict[Key.warningThreshold.rawValue] as? Int,
                  reporter: dict[Key.reporter.rawValue] as? String ??
                    XcodeReporter.identifier,
                  ruleList: ruleList,
                  configuredRules: configuredRules,
                  swiftlintVersion: dict[Key.swiftlintVersion.rawValue] as? String,
                  cachePath: cachePath ?? dict[Key.cachePath.rawValue] as? String)
    }

    public init(path: String = Configuration.fileName, rootPath: String? = nil,
                optional: Bool = true, quiet: Bool = false, enableAllRules: Bool = false, cachePath: String? = nil) {
        let fullPath: String
        if let rootPath = rootPath {
            fullPath = path.bridge().absolutePathRepresentation(rootDirectory: rootPath)
        } else {
            fullPath = path.bridge().absolutePathRepresentation()
        }

        let fail = { (msg: String) in
            queuedPrintError("\(fullPath):\(msg)")
            fatalError("Could not read configuration file at path '\(fullPath)'")
        }
        if path.isEmpty || !FileManager.default.fileExists(atPath: fullPath) {
            if !optional { fail("File not found.") }
            self.init(enableAllRules: enableAllRules, cachePath: cachePath)!
            self.rootPath = rootPath
            return
        }
        do {
            let yamlContents = try String(contentsOfFile: fullPath, encoding: .utf8)
            let dict = try YamlParser.parse(yamlContents)
            if !quiet {
                queuedPrintError("Loading configuration from '\(path)'")
            }
            self.init(dict: dict, enableAllRules: enableAllRules, cachePath: cachePath)!
            configurationPath = fullPath
            self.rootPath = rootPath
            setCached(atPath: fullPath)
            return
        } catch YamlParserError.yamlParsing(let message) {
            fail(message)
        } catch {
            fail("\(error)")
        }
        self.init(enableAllRules: enableAllRules, cachePath: cachePath)!
        setCached(atPath: fullPath)
    }

    public func lintablePaths(inPath path: String, fileManager: LintableFileManager = FileManager.default) -> [String] {
        // If path is a Swift file, skip filtering with excluded/included paths
        if path.bridge().isSwiftFile() && path.isFile {
            return [path]
        }
        let pathsForPath = included.isEmpty ? fileManager.filesToLint(inPath: path, rootDirectory: nil) : []
        let excludedPaths = excluded.flatMap {
            fileManager.filesToLint(inPath: $0, rootDirectory: rootPath)
        }
        let includedPaths = included.flatMap {
            fileManager.filesToLint(inPath: $0, rootDirectory: rootPath)
        }
        return (pathsForPath + includedPaths).filter({ !excludedPaths.contains($0) })
    }

    public func lintableFiles(inPath path: String) -> [File] {
        return lintablePaths(inPath: path).flatMap { File(path: $0) }
    }
}

private func validateRuleIdentifiers(configuredRules: [Rule], disabledRules: [String]) -> [String] {
    // Validate that all rule identifiers map to a defined rule
    let validRuleIdentifiers = configuredRules.map { type(of: $0).description.identifier }

    let invalidRules = disabledRules.filter { !validRuleIdentifiers.contains($0) }
    if !invalidRules.isEmpty {
        for invalidRule in invalidRules {
            queuedPrintError("configuration error: '\(invalidRule)' is not a valid rule identifier")
        }
        let listOfValidRuleIdentifiers = validRuleIdentifiers.joined(separator: "\n")
        queuedPrintError("Valid rule identifiers:\n\(listOfValidRuleIdentifiers)")
    }

    return validRuleIdentifiers
}

private func containsDuplicateIdentifiers(_ identifiers: [String]) -> Bool {
    // Validate that rule identifiers aren't listed multiple times
    if Set(identifiers).count != identifiers.count {
        let duplicateRules = identifiers.reduce([String: Int]()) { accu, element in
            var accu = accu
            accu[element] = (accu[element] ?? 0) + 1
            return accu
        }.filter { $0.1 > 1 }
        queuedPrintError(duplicateRules.map { rule in
            "configuration error: '\(rule.0)' is listed \(rule.1) times"
        }.joined(separator: "\n"))
        return true
    }

    return false
}

private func warnAboutDeprecations(configurationDictionary dict: [String: Any],
                                   disabledRules: [String] = [],
                                   optInRules: [String] = [],
                                   whitelistRules: [String] = [],
                                   ruleList: RuleList) {

    // Deprecation warning for "enabled_rules"
    if dict[Configuration.Key.enabledRules.rawValue] != nil {
        queuedPrintError("'\(Configuration.Key.enabledRules.rawValue)' has been renamed to " +
            "'\(Configuration.Key.optInRules.rawValue)' and will be completely removed in a " +
            "future release.")
    }

    // Deprecation warning for "use_nested_configs"
    if dict[Configuration.Key.useNestedConfigs.rawValue] != nil {
        queuedPrintError("Support for '\(Configuration.Key.useNestedConfigs.rawValue)' has " +
            "been deprecated and its value is now ignored. Nested configuration files are " +
            "now always considered.")
    }

    // Deprecation warning for rules
    let deprecatedRulesIdentifiers = ruleList.list.flatMap { (identifier, rule) -> [(String, String)] in
        return rule.description.deprecatedAliases.map { ($0, identifier) }
    }

    let userProvidedRuleIDs = Set(disabledRules + optInRules + whitelistRules)
    let deprecatedUsages = deprecatedRulesIdentifiers.filter { deprecatedIdentifier, _ in
        return dict[deprecatedIdentifier] != nil || userProvidedRuleIDs.contains(deprecatedIdentifier)
    }

    for (deprecatedIdentifier, identifier) in deprecatedUsages {
        queuedPrintError("'\(deprecatedIdentifier)' rule has been renamed to '\(identifier)' and will be " +
            "completely removed in a future release.")
    }
}

// Mark - == Implementation

public func == (lhs: Configuration, rhs: Configuration) -> Bool {
    return (lhs.excluded == rhs.excluded) &&
           (lhs.included == rhs.included) &&
           (lhs.reporter == rhs.reporter) &&
           (lhs.configurationPath == rhs.configurationPath) &&
           (lhs.rootPath == lhs.rootPath) &&
           (lhs.rules == rhs.rules)
}
