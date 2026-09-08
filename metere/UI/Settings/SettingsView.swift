//
//  SettingsView.swift
//  metere
//

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings = .shared
    @ObservedObject var appState: AppState = .shared
    @ObservedObject var updateManager: UpdateManager = .shared

    @State private var showingClearTodayAlert = false
    @State private var showingClearAllAlert = false

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AcousticCalibrationTab(appState: appState)
                .tabItem {
                    Label("Calibration", systemImage: "waveform.badge.magnifyingglass")
                }

            DataSettingsTab(
                appState: appState,
                showingClearTodayAlert: $showingClearTodayAlert,
                showingClearAllAlert: $showingClearAllAlert
            )
            .tabItem {
                Label("Data & Privacy", systemImage: "externaldrive")
            }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }

            UpdatesSettingsTab(settings: settings, updateManager: appState.updateManager)
                .tabItem {
                    Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 580, height: 540)
        .padding()
        .sheet(isPresented: $updateManager.showingUpdateSheet) {
            UpdateSheetView(updateManager: updateManager)
        }
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Launch Metere at login", isOn: $settings.launchAtLogin)

                Toggle("Show digital level (dBFS) in menu bar", isOn: $settings.showDecibelsInMenuBar)
            } header: {
                Text("System & Menu Bar")
            }

            Section {
                Toggle("Enable High-Volume Protection", isOn: $settings.enableHighVolumeProtection)

                if settings.enableHighVolumeProtection {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Warning Threshold")
                            Spacer()
                            Text("\(Int(round(settings.highVolumeThreshold * 100)))%")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        Slider(value: $settings.highVolumeThreshold, in: 0.70...0.95, step: 0.05)
                    }

                    Toggle("Auto-Rollback Volume to Safety Threshold", isOn: $settings.autoRollbackHighVolume)

                    Text("When audio is playing through headphones and volume exceeds your threshold, Metere sends an immediate system alert. If Auto-Rollback is enabled, volume is automatically pulled back to prevent hearing damage.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("High-Volume Hearing Protection")
            }

            Section {
                Picker("Continuous Playback Break Reminder", selection: $settings.breakReminderInterval) {
                    Text("Off").tag(0.0)
                    Text("After 30 minutes active").tag(1800.0)
                    Text("After 45 minutes active").tag(2700.0)
                    Text("After 60 minutes active").tag(3600.0)
                    Text("After 90 minutes active").tag(5400.0)
                }
                .pickerStyle(.menu)

                Toggle("Notify when audio output device changes", isOn: $settings.notifyOnRouteChange)

                Text("Break reminders accumulate strictly during active continuous playback. Paused intervals and idle connections do not trigger reminders.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Smart Break Reminders")
            }

            Section {
                Picker("Sampling Interval", selection: $settings.samplingInterval) {
                    Text("1 second (Responsive)").tag(1.0)
                    Text("2 seconds (Recommended)").tag(2.0)
                    Text("5 seconds (Battery Saver)").tag(5.0)
                }
                .pickerStyle(.menu)

                Text("Active listening time is tracked strictly while audio is actively playing through connected headphones.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Measurement Frequency")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            VStack(spacing: 4) {
                Text("Metere")
                    .font(.system(size: 18, weight: .bold))
                Text("Version 1.2 · Native macOS Audio Monitor")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Privacy: 100% local-first. All listening history stays securely on your Mac.", systemImage: "lock.shield.fill")
                Label("Metrology: No synthetic SPL. Volume % and dBFS are never treated as ear-level dBA.", systemImage: "checkmark.seal.fill")
                Label("WHO Exposure: Evaluated strictly against empirical coupler calibration profiles.", systemImage: "ear.badge.checkmark")
                Label("Recovery: Psychoacoustic quiet-rest modeling after continuous sessions.", systemImage: "leaf.fill")
                Label("Protection: Optional high-volume alert & auto-rollback safeguards.", systemImage: "shield.lefthalf.filled")
            }
            .font(.system(size: 11.5))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AcousticCalibrationTab: View {
    @ObservedObject var appState: AppState

    // Wired Headphone Calculator State
    @State private var selectedDACPreset: DACPreset = .macBookProHighGain
    @State private var customVrms: String = "2.0"
    @State private var customOutputImpedance: String = "1.0"
    @State private var headphoneImpedanceText: String = "80"
    @State private var sensitivityText: String = "96"
    @State private var selectedUnit: SensitivityUnit = .dbPerMilliwatt
    @State private var calibrationAppliedSuccess: Bool = false

    private var activeVrms: Double {
        if selectedDACPreset == .custom {
            return Double(customVrms) ?? 2.0
        }
        return selectedDACPreset.maxOutputVoltageVrms
    }

    private var activeOutputZ: Double {
        if selectedDACPreset == .custom {
            return Double(customOutputImpedance) ?? 1.0
        }
        return selectedDACPreset.outputImpedanceOhms
    }

    private var activeImpedance: Double {
        Double(headphoneImpedanceText) ?? 80.0
    }

    private var activeSensitivity: Double {
        Double(sensitivityText) ?? 96.0
    }

    private var calculatedMaxSPL: Double {
        WiredHeadphonePhysicsCalculator.calculateMaxSPL(
            vrms: activeVrms,
            outputImpedance: activeOutputZ,
            headphoneImpedance: activeImpedance,
            sensitivity: activeSensitivity,
            unit: selectedUnit
        )
    }

    var body: some View {
        Form {
            Section {
                if let cal = appState.activeCalibrationRecord {
                    LabeledContent("Calibration Device", value: cal.deviceModel)
                    LabeledContent("Device UID", value: cal.deviceUID)
                    LabeledContent("Calibration Type", value: cal.isModelLevelOnly ? "Model-level estimate" : "Device-specific measurement")
                    LabeledContent("Reference SPL", value: String(format: "%.1f dBA", cal.referenceSPL))
                    LabeledContent("Reference Volume", value: "\(Int(round(cal.calibratedVolume * 100)))%")
                    LabeledContent("Reference Digital Level", value: String(format: "%.1f dBFS", cal.calibratedDBFS))
                    LabeledContent("Operating Envelope", value: String(format: "Vol ±%.0f%% · Level ±%.1f dB", cal.supportedVolumeTolerance * 100, cal.supportedDBFSTolerance))
                    LabeledContent("Uncertainty", value: String(format: "±%.1f dB", cal.uncertaintyDB))
                    LabeledContent("Methodology", value: cal.methodology.displayName)
                    LabeledContent("Calibration Date", value: cal.timestamp.formatted(date: .abbreviated, time: .shortened))

                    Button("Remove Calibration Record", role: .destructive) {
                        appState.activeCalibrationRecord = nil
                        calibrationAppliedSuccess = false
                    }
                } else {
                    LabeledContent("Status", value: "Calibration required")
                    LabeledContent("Active Output", value: appState.activeHeadphone?.name ?? "None")
                    LabeledContent("Acoustic SPL", value: "Not measured")
                    LabeledContent("WHO Exposure", value: "Unavailable")
                }
            } header: {
                Text("Active Calibration Profile")
            }

            Section {
                Picker("Audio Output / DAC", selection: $selectedDACPreset) {
                    ForEach(DACPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }

                if selectedDACPreset == .custom {
                    HStack {
                        Text("Custom DAC Max Voltage (Vrms):")
                        TextField("2.0", text: $customVrms)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("Custom Output Impedance (Ω):")
                        TextField("1.0", text: $customOutputImpedance)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                }

                HStack {
                    Text("Headphone Nominal Impedance (Ω):")
                    TextField("80", text: $headphoneImpedanceText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                }

                HStack {
                    Text("Sensitivity:")
                    TextField("96", text: $sensitivityText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(SensitivityUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Theoretical Max SPL at 100% Volume:")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(String(format: "%.1f dBA SPL", calculatedMaxSPL))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.accentColor)
                    }

                    Text("Generates empirical multi-point operating envelope (30%–80% vol) with ±3.0 dB coupler uncertainty. Zero extrapolation outside this range.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                HStack {
                    Button("Apply to Connected Headphone") {
                        let devName = appState.activeHeadphone?.name ?? "Wired Headphones"
                        let devUID = appState.activeHeadphone?.uid ?? "AppleHDAEngineOutput:1,0,1,1:0"
                        let record = WiredHeadphonePhysicsCalculator.generateCalibrationRecord(
                            deviceUID: devUID,
                            deviceModel: devName,
                            vrms: activeVrms,
                            outputImpedance: activeOutputZ,
                            headphoneImpedance: activeImpedance,
                            sensitivity: activeSensitivity,
                            unit: selectedUnit
                        )
                        appState.activeCalibrationRecord = record
                        calibrationAppliedSuccess = true
                    }
                    .buttonStyle(.borderedProminent)

                    if calibrationAppliedSuccess {
                        Label("Profile Applied", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } header: {
                Text("Wired Headphone Calibration Assistant")
            }

            Section {
                Text("Acoustic calibration is required to estimate ear-level sound pressure (dBA SPL). Digital audio level (dBFS) and macOS volume are not measurements of physical sound pressure.\n\nMetere strictly refuses to extrapolate SPL beyond the empirical conditions demonstrated during calibration. Changing volume or digital level outside the calibrated operating envelope will immediately disable SPL and WHO exposure estimates.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Metrological Principles")
            }
        }
        .formStyle(.grouped)
    }
}

private struct DataSettingsTab: View {
    @ObservedObject var appState: AppState
    @Binding var showingClearTodayAlert: Bool
    @Binding var showingClearAllAlert: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent("Active Day") {
                    Text(DailyStatistics.makeDateKey(for: Date()))
                        .foregroundColor(.secondary)
                }

                LabeledContent("Today's Sessions Recorded") {
                    Text("\(appState.todaySessionCount)")
                        .foregroundColor(.secondary)
                }

                LabeledContent("Total Active Playback Today") {
                    Text(appState.formattedTodayDuration)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Current Session State")
            }

            Section {
                HStack(spacing: 12) {
                    Button {
                        let csv = DataExportManager.shared.generateCSV(from: appState.historicalSessions)
                        DataExportManager.shared.presentSavePanel(defaultFilename: "metere_listening_history.csv", content: csv)
                    } label: {
                        Label("Export as CSV", systemImage: "tablecells")
                    }

                    Button {
                        if let data = try? DataExportManager.shared.generateJSON(from: PersistedData(dailyRecords: appState.sessionManager.allDailyRecords, activeSession: appState.sessionManager.activeSession)),
                           let jsonStr = String(data: data, encoding: .utf8) {
                            DataExportManager.shared.presentSavePanel(defaultFilename: "metere_listening_history.json", content: jsonStr)
                        }
                    } label: {
                        Label("Export as JSON", systemImage: "curlybraces")
                    }
                }

                Text("Export all recorded listening sessions, timestamps, duration, and measurable attenuation levels to your local disk.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Export History")
            }

            Section {
                HStack {
                    Button("Clear Today's Data", role: .destructive) {
                        showingClearTodayAlert = true
                    }
                    .confirmationDialog(
                        "Clear Today's Data?",
                        isPresented: $showingClearTodayAlert,
                        titleVisibility: .visible
                    ) {
                        Button("Clear Today", role: .destructive) {
                            appState.sessionManager.clearTodayData()
                        }
                    } message: {
                        Text("This will reset today's active playback sessions and exposure counters. Historical days remain intact.")
                    }

                    Spacer()

                    Button("Reset All History", role: .destructive) {
                        showingClearAllAlert = true
                    }
                    .confirmationDialog(
                        "Reset All History?",
                        isPresented: $showingClearAllAlert,
                        titleVisibility: .visible
                    ) {
                        Button("Delete Everything", role: .destructive) {
                            appState.sessionManager.clearAllHistory()
                        }
                    } message: {
                        Text("This removes all saved listening sessions and historical exposure data permanently.")
                    }
                }
            } header: {
                Text("Data Management")
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdatesSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 38))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Metere for macOS")
                            .font(.system(size: 15, weight: .semibold))

                        Text("Current Version: \(SemanticVersion.currentAppVersion.description) (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        updateManager.checkForUpdates(userInitiated: true)
                    } label: {
                        if case .checking = updateManager.status {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Checking…")
                            }
                        } else {
                            Text("Check for Updates Now")
                        }
                    }
                    .disabled(updateManager.status == .checking)
                }
                .padding(.vertical, 4)

                // Status Message Row
                updateStatusRow
            } header: {
                Text("App Version & Update Status")
            }

            Section {
                Toggle("Automatically check for updates", isOn: $settings.automaticallyCheckForUpdates)

                if settings.automaticallyCheckForUpdates {
                    Picker("Check Frequency", selection: $settings.updateCheckInterval) {
                        Text("Every Launch").tag(0.0)
                        Text("Daily (Recommended)").tag(86400.0)
                        Text("Weekly").tag(604800.0)
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Include pre-releases (Beta versions)", isOn: $settings.includePrereleases)

                if let lastCheck = updateManager.lastCheckDate {
                    LabeledContent("Last Checked") {
                        Text(lastCheck.formatted(date: .abbreviated, time: .shortened))
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Automation")
            }

            Section {
                HStack {
                    TextField("GitHub Repository", text: $settings.updateRepository)
                        .textFieldStyle(.roundedBorder)

                    Button("Default") {
                        settings.updateRepository = "halite-inc/metere"
                    }
                    .disabled(settings.updateRepository == "halite-inc/metere")
                }

                Text("Metere queries this repository's public GitHub releases feed to find updates, download assets, and view release notes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Release Channel Source")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateManager.status {
        case .idle:
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("Ready to check for updates.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Querying GitHub for latest releases…")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case .upToDate:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Metere \(SemanticVersion.currentAppVersion.description) is currently the newest version available.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
            }
        case .available(let update):
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("New version available: \(update.version.description)")
                        .font(.system(size: 12, weight: .semibold))
                    Text(update.releaseTitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("View Update…") {
                    updateManager.showingUpdateSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .downloading(let progress, _, let totalBytes):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading update…")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    if totalBytes > 0 {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                ProgressView(value: progress)
            }
        case .downloaded:
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.green)
                Text("Update downloaded.")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Install Now") {
                    updateManager.installDownloadedUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Launching installer…")
                    .font(.system(size: 12))
            }
        case .error(let msg):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
            }
        }
    }
}

