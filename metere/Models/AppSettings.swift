//
//  AppSettings.swift
//  metere
//

import Foundation
import Combine
import ServiceManagement

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private enum Keys {
        static let launchAtLogin = "metere_launchAtLogin"
        static let showDecibelsInMenuBar = "metere_showDecibelsInMenuBar"
        static let samplingInterval = "metere_samplingInterval"
        static let decibelCalibrationOffset = "metere_decibelCalibrationOffset"
        static let safeThresholdDB = "metere_safeThresholdDB"
        static let breakReminderInterval = "metere_breakReminderInterval"
        static let notifyOnRouteChange = "metere_notifyOnRouteChange"
        static let enableHighVolumeProtection = "metere_enableHighVolumeProtection"
        static let highVolumeThreshold = "metere_highVolumeThreshold"
        static let autoRollbackHighVolume = "metere_autoRollbackHighVolume"
        static let automaticallyCheckForUpdates = "metere_automaticallyCheckForUpdates"
        static let updateCheckInterval = "metere_updateCheckInterval"
        static let includePrereleases = "metere_includePrereleases"
        static let lastUpdateCheckDate = "metere_lastUpdateCheckDate"
        static let skippedVersion = "metere_skippedVersion"
        static let updateRepository = "metere_updateRepository"
    }

    private let defaults: UserDefaults

    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published public var showDecibelsInMenuBar: Bool {
        didSet {
            defaults.set(showDecibelsInMenuBar, forKey: Keys.showDecibelsInMenuBar)
        }
    }

    @Published public var samplingInterval: Double {
        didSet {
            defaults.set(samplingInterval, forKey: Keys.samplingInterval)
        }
    }

    @Published public var decibelCalibrationOffset: Double {
        didSet {
            defaults.set(decibelCalibrationOffset, forKey: Keys.decibelCalibrationOffset)
        }
    }

    @Published public var safeThresholdDB: Double {
        didSet {
            defaults.set(safeThresholdDB, forKey: Keys.safeThresholdDB)
        }
    }

    @Published public var breakReminderInterval: Double {
        didSet {
            defaults.set(breakReminderInterval, forKey: Keys.breakReminderInterval)
        }
    }

    @Published public var notifyOnRouteChange: Bool {
        didSet {
            defaults.set(notifyOnRouteChange, forKey: Keys.notifyOnRouteChange)
        }
    }

    @Published public var enableHighVolumeProtection: Bool {
        didSet {
            defaults.set(enableHighVolumeProtection, forKey: Keys.enableHighVolumeProtection)
        }
    }

    @Published public var highVolumeThreshold: Float {
        didSet {
            defaults.set(highVolumeThreshold, forKey: Keys.highVolumeThreshold)
        }
    }

    @Published public var autoRollbackHighVolume: Bool {
        didSet {
            defaults.set(autoRollbackHighVolume, forKey: Keys.autoRollbackHighVolume)
        }
    }

    @Published public var automaticallyCheckForUpdates: Bool {
        didSet {
            defaults.set(automaticallyCheckForUpdates, forKey: Keys.automaticallyCheckForUpdates)
        }
    }

    @Published public var updateCheckInterval: Double {
        didSet {
            defaults.set(updateCheckInterval, forKey: Keys.updateCheckInterval)
        }
    }

    @Published public var includePrereleases: Bool {
        didSet {
            defaults.set(includePrereleases, forKey: Keys.includePrereleases)
        }
    }

    @Published public var lastUpdateCheckDate: Date? {
        didSet {
            defaults.set(lastUpdateCheckDate, forKey: Keys.lastUpdateCheckDate)
        }
    }

    @Published public var skippedVersion: String? {
        didSet {
            defaults.set(skippedVersion, forKey: Keys.skippedVersion)
        }
    }

    @Published public var updateRepository: String {
        didSet {
            defaults.set(updateRepository, forKey: Keys.updateRepository)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.showDecibelsInMenuBar: true,
            Keys.samplingInterval: 2.0,
            Keys.decibelCalibrationOffset: 0.0,
            Keys.safeThresholdDB: 80.0,
            Keys.breakReminderInterval: 0.0, // 0 = Off
            Keys.notifyOnRouteChange: false,
            Keys.enableHighVolumeProtection: false,
            Keys.highVolumeThreshold: 0.80,
            Keys.autoRollbackHighVolume: false,
            Keys.automaticallyCheckForUpdates: true,
            Keys.updateCheckInterval: 86400.0, // 24 hours
            Keys.includePrereleases: false,
            Keys.updateRepository: "halite-inc/metere"
        ])

        // Determine actual system launch at login status if available
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            if status == .enabled {
                self.launchAtLogin = true
            } else if defaults.object(forKey: Keys.launchAtLogin) != nil {
                self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
            } else {
                self.launchAtLogin = false
            }
        } else {
            self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        }

        self.showDecibelsInMenuBar = defaults.bool(forKey: Keys.showDecibelsInMenuBar)
        self.samplingInterval = defaults.double(forKey: Keys.samplingInterval)
        self.decibelCalibrationOffset = defaults.double(forKey: Keys.decibelCalibrationOffset)
        self.safeThresholdDB = defaults.double(forKey: Keys.safeThresholdDB)
        self.breakReminderInterval = defaults.double(forKey: Keys.breakReminderInterval)
        self.notifyOnRouteChange = defaults.bool(forKey: Keys.notifyOnRouteChange)
        self.enableHighVolumeProtection = defaults.bool(forKey: Keys.enableHighVolumeProtection)
        let savedThresh = defaults.float(forKey: Keys.highVolumeThreshold)
        self.highVolumeThreshold = savedThresh > 0 ? savedThresh : 0.80
        self.autoRollbackHighVolume = defaults.bool(forKey: Keys.autoRollbackHighVolume)

        self.automaticallyCheckForUpdates = defaults.bool(forKey: Keys.automaticallyCheckForUpdates)
        let savedInterval = defaults.double(forKey: Keys.updateCheckInterval)
        self.updateCheckInterval = savedInterval > 0 ? savedInterval : 86400.0
        self.includePrereleases = defaults.bool(forKey: Keys.includePrereleases)
        self.lastUpdateCheckDate = defaults.object(forKey: Keys.lastUpdateCheckDate) as? Date
        self.skippedVersion = defaults.string(forKey: Keys.skippedVersion)
        let savedRepo = defaults.string(forKey: Keys.updateRepository)
        self.updateRepository = (savedRepo?.isEmpty == false) ? savedRepo! : "halite-inc/metere"
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                print("[AppSettings] Notice: SMAppService registration: \(error.localizedDescription)")
            }
        }
    }
}
